% Run end-to-end text recognition on precomputed line-level bboxes using 
% beam search
% return the results in terms of precision, recall and fscore.
function printOutput(dataset, model, std_cost, narrow_cost, split_cost, THRESH)

close all;

% Save as variables all model's features
D1 = model.D;
M1 = model.M;
P1 = model.P;
mu = model.mu;
sig = model.sig; 
params = model.params;
netconfig = model.netconfig;

% directory of files holding line-level bounding boxes generated by
% detector
gt_dir = 'images_winebottles/gt/';
bottles_dir = 'images_winebottles/bottles/';
lex_dir = 'lexicon/';
words_wine = 159;

% load images gt
files1 = dir(fullfile(gt_dir,'*.jpg'));
files2 = dir(fullfile(gt_dir,'*.png'));
files = [files1;files2];
gt_names = {files.name};
tot_gt = numel(gt_names);

% load images bottles
files = [];
for i = 1:length(gt_names)
    name = gt_names{i}(1:end-4);
    files1 = dir(fullfile(bottles_dir,name,'/*.jpg'));
    files2 = dir(fullfile(bottles_dir,name,'/*.png'));
    files = [files;files1;files2];
end
bottles_names = {files.name};
tot_bottles = numel(bottles_names);
fprintf('Loaded file names.\n');

if strcmp(dataset,'gt') == 1
    filenames = gt_names;
    tot_images = tot_gt;
    bbox_dir = 'precomputedLineBoxes/winebottles_gt/';
elseif strcmp(dataset,'bottles') == 1
    filenames = bottles_names;
    tot_images = tot_bottles;
    bbox_dir = 'precomputedLineBoxes/winebottles_bottles/';
end

% load lexicon
lex = cell(20,1);
from = 1;
fid = fopen([lex_dir, 'lex-wine.txt']);
for i = from:words_wine
    lex{i} = fgetl(fid);
end
fclose(fid);
fprintf('Loaded lexicon.\n');

precision = []; recall = []; fscore = [];
global scoreTable wordsTable;
global c_std c_narrow;
c_std = std_cost;
c_narrow = narrow_cost;
c_split = split_cost;

if ~exist(['results_' dataset '.txt'])
    edit(['results_' dataset '.txt']);
end
fid = fopen(['results_' dataset '.txt'], 'w');

for THRESHidx = 1:length(THRESH)
    totalTrueBbox = 0;
    totalPredBbox = 0;
    totalGoodBbox = 0;
    thresh = THRESH(THRESHidx);
    for i = 1:tot_images
        imgname = filenames{i}; 
        fprintf('Reading %s (-%d).\n', imgname, tot_images-i);
        fprintf(fid, '%s: ', imgname); 
        pathimg = fileparts(which(imgname));
        img = imread([pathimg '\' imgname]);
        info = imfinfo([pathimg '\' imgname]);
        origimg = img;
        imname = [imgname(1:end-4) '.mat']; % filename of line-level bbox info
        wbboxes = []; % predicted word bboxes
        predwords = []; % predicted labels
       
        
        if ~exist([bbox_dir imname], 'file')
            error('precomputed line-level bbox not found. Refer to README and detectorDemo/runDetectorFull.m');
        end
        load([bbox_dir imname]);
        % precomputed line-level bboxes and candidate spaces
        %visualizeBoxes(img, response);
        bboxes = response.bbox;
        spaces = response.spaces;
        numbbox = size(bboxes,1);
        [height, width, depth] = size(img);
        for bidx = 1:numbbox % for every line-level bounding box
            % prune out candidate line bboxes with low score or too many
            % spaces (15). This is valid assumption as lines are almost always
            % shorter than 10 words in natural scenes
            if bboxes(bidx,5)>0.7 && length(spaces(bidx).locations)<15
                x = bboxes(bidx,1);
                y = bboxes(bidx,2);
                w = bboxes(bidx,3);
                h = bboxes(bidx,4);
                % four corners of the bounding box
                % aa---------------bb
                %  |                |
                %  |                |
                %  |                |
                %  cc--------------dd
                aa = [max(y,1),max(x,1)];
                bb = [max(y,1), min(x+w, width)];
                cc = [min(y+h, height), max(x,1)];
                dd = [min(y+h, height), min(x+w, width)];
                % candidate spaces
                locations = spaces(bidx).locations;
                spacescores = spaces(bidx).scores;
                locations = locations(spacescores>0.7);
                spacescores = spacescores(spacescores>0.7);
                [orig_sorted_locations sortidx]= sort(locations(:),'ascend');
                spacescores = spacescores(sortidx);
                % resize and pad the line-level bbox
                if info.BitDepth == 8 % if already a gray image, or not
                    longimg = img(aa(1): cc(1), aa(2):bb(2), :);
                else
                    longimg = rgb2gray(img(aa(1): cc(1), aa(2):bb(2), :)); 
                end
                stdimg = imresize(longimg, [32, NaN]);
                [subheight subwidth] = size(longimg);
                [stdheight stdwidth] = size(stdimg);

                % chop the line into segments using cadidate spaces
                sorted_locations = round(orig_sorted_locations/subheight*stdheight);
                segs = [  [1; sorted_locations] [sorted_locations; stdwidth]];
                std_starts = [1; sorted_locations];
                std_ends = [sorted_locations; stdwidth];

                orig_starts = [1; orig_sorted_locations];
                orig_ends = [orig_sorted_locations; subwidth];
                numbeams = 60;
                states = [];
                numsegs = size(segs,1);
                scoreTable = ones(numsegs+1, numsegs+1)*(-99); % -99 is an arbitary number chosen to indicate an empty position
                wordsTable = cell(numsegs+1, numsegs+1);
                curr = 1;
                % compute the recognition score for the current
                % line level bbox
                origscores =  getRecogScores_convnet(longimg, D1, M1, P1, mu,sig, params, netconfig);
                % perform beam search on the line
                while isempty(states) || curr<=size(segs,1)
                    [newstates curr]= beam_search_step(states, curr, origscores, segs, spacescores, numbeams, lex, thresh, c_split);
                    states = newstates;
                end
                %fprintf('prediction: ')
                %states{1}

                if length(states{1}.path)==1 && states{1}.path(1)==2
                    states{1}.path(1) = 5;
                end

                % now generate word bboxes from beam search results
                startings = states{1}.path==1 | states{1}.path == 2;
                endings  = states{1}.path==1 | states{1}.path == 3;
                assert(sum(startings) == sum(endings));
                realsegs = [orig_starts(startings) orig_ends(endings)];
                realstdsegs = [std_starts(startings) std_ends(endings)]; % starting and endings in the std img

                currwords = [];%predicted words in the current line
                for ww = 1:length(states{1}.words)
                    if ~isempty(states{1}.words{ww})
                        currwords{end+1} = states{1}.words{ww};
                    end
                end
                predscores = states{1}.scores(states{1}.scores>thresh);
                for ss = 1:length(currwords)
                    tempbbox = zeros(1,5);
                    tempbbox(2) = aa(1);
                    tempbbox(4) = subheight;
                    subscores = origscores(:, realstdsegs(ss,1):realstdsegs(ss,2));
                    % compute actual left and right bounds for the current segment
                    [~, ~, ~, bounds] =  score2WordBounds(subscores, currwords(ss));
                    tempbbox(1) = realsegs(ss,1)+aa(2)-1+round((bounds(1)-1)/32*subheight); % adjust x position
                    tempbbox(3) = realsegs(ss,2)-realsegs(ss,1)+1 - round((bounds(1)+bounds(2)-1)/32*subheight); % adjust width
                    tempbbox(5) = predscores(ss);
                    wbboxes = [wbboxes;tempbbox];
                    predwords{end+1} = currwords{ss};
                end
            end
        end

        if ~isempty(wbboxes)
            %remove wbboxes with low recognition scores
            bad_idx = wbboxes(:,end)<thresh; 
            wbboxes(bad_idx, :) = [];
            predwords(bad_idx) = [];
            
            %sort wbboxes in recognition scores
            matchScores = wbboxes(:,end);
            [~, score_idx] = sort(matchScores, 'descend');
            wbboxes = wbboxes(score_idx,:);
            predwords = predwords(score_idx);
            
            numbbox = size(wbboxes,1);
            pred_taken = zeros(numbbox,1);
        end
        
        numbbox = size(wbboxes,1);
        % iterate over predicted word bounding boxes
        for bidx = 1:numbbox
            if pred_taken(bidx)==0
                x = wbboxes(bidx,1);
                y = wbboxes(bidx,2);
                w = wbboxes(bidx,3);
                h = wbboxes(bidx,4);
                aa = [max(y,1),max(x,1)];% upper left corner
                bb = [max(y,1), min(x+w, width)];% upper right corner
                cc = [min(y+h, height), max(x,1)];% lower left corner

                %fprintf('predword  %s, Recog Score  %2.3f\n', predwords{bidx}, wbboxes(bidx,end));
                fprintf(fid, '%s ', predwords{bidx});
                
                % eliminate all worse wbboxes that overlap with the current one
                % by 1/2 of the area of either bbox.
                for worse_idx = (bidx+1):numbbox % wbboxes that are worse than the current one
                    if pred_taken(worse_idx)==0
                        x2 = wbboxes(worse_idx,1);
                        y2 = wbboxes(worse_idx,2);
                        w2 = wbboxes(worse_idx,3);
                        h2 = wbboxes(worse_idx,4);
                        aa2 = [max(y2,1),max(x2,1)]; % upper left corner
                        bb2 = [max(y2,1), min(x2+w2, width)];% upper right
                        cc2 = [min(y2+h2, height), max(x2,1)];% lower left
                        pred_y1 = aa(1); pred_y2 = cc(1);
                        pred_x1 = aa(2); pred_x2 = bb(2);
                        pred_rec = [pred_x1, pred_y1, pred_x2-pred_x1+1, pred_y2-pred_y1+1];
                        pred2_y1 = aa2(1); pred2_y2 = cc2(1);
                        pred2_x1 = aa2(2); pred2_x2 = bb2(2);
                        pred2_rec = [pred2_x1, pred2_y1, pred2_x2-pred2_x1+1, pred2_y2-pred2_y1+1];
                        intersect_area = rectint(pred_rec,pred2_rec);
                        pred_area = pred_rec(3)* pred_rec(4);
                        pred2_area = pred2_rec(3)* pred2_rec(4);
                        if intersect_area>0.5*pred_area || intersect_area>0.5*pred2_area
                            pred_taken(worse_idx) = 1; % worse bbox did not survive NMS
                        end
                    end
                end
             
                
            end
        end    
        fprintf(fid, '\n');
    end
end

fclose(fid);