clear all;
close all;

%% Search for the results of bottles and gt and put them in cell array

addpath(genpath('.'));
bottles_dir = 'images_winebottles/bottles/';
gt_dir = 'images_winebottles/gt/';

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
    files1 = dir(fullfile(bottles_dir, name, '/*.jpg'));
    files2 = dir(fullfile(bottles_dir, name, '/*.png'));
    files = [files;files1;files2];
end
bottles_names = {files.name};
tot_bottles = numel(bottles_names);
fprintf('Loaded file names.\n');

fid = fopen('results_bottles_okay.txt');
if fid == -1
    error('Cannot open file.\n')
end
words = cell(1);
words_bottles = cell(tot_bottles,1);
for i = 1:tot_bottles
    words{i} = fgetl(fid);
    splits = split(words{i});
    names = size(splits);
    j = 1;
    while ~isempty(splits{j})
        words_bottles{i,j} = splits{j};
        j = j + 1;
    end
end
fclose(fid);
fprintf('Bottles results loaded.\n');

fid = fopen('results_gt_okay.txt');
if fid == -1
    error('Cannot open file.\n')
end
words = cell(1);
words_gt = cell(tot_gt,1);
for i = 1:tot_gt
    words{i} = fgetl(fid);
    splits = split(words{i});
    names = size(splits);
    j = 1;
    while ~isempty(splits{j})
        words_gt{i,j} = splits{j};
        j = j + 1;
    end
end
fclose(fid);
fprintf('GT results loaded.\n');

%% Find if words in results_gt are also in results_bottles (and in wich position)

% Determine number of columns for words_bottles and words_gt
[~,col_bottles] = size(words_bottles);
[~,col_gt] = size(words_gt);

% Create list of gt_names without extension to match the folders in which
% bottles images are contained 
for i = 1:tot_gt
    gt_names_without_ext{i} = gt_names{i}(1:end-4);
end


word_score = ones(tot_bottles,col_bottles,col_gt)*100;
final_index = zeros(tot_gt,col_gt-1);
matches = cell(tot_bottles,0);
fid = fopen('validation_results.txt', 'w');
for i = 1:tot_bottles
    m = 1;
    % Extract image name
    name = split(words_bottles{i,1},':');
    imgname = name{1};
    % Extract corresponding image in gt dataset
    path = fileparts(which(imgname));
    gtname = split(path,'\');
    gtname = gtname{end};
    index = find(strcmp(gt_names_without_ext, gtname));
    fprintf(fid, '%s\n', words_bottles{i,1});
    % if there is at least one word in results_gt for this bottle
    if ~isempty(words_gt{index,2})
        matched_bottles = [1,col_bottles-1];
        final_scores = ones(col_bottles,col_gt-1)*100;
        j = 2;
        while j <= col_bottles & ~isempty(words_bottles{i,j})
            z = 2;
            while z <= col_gt & ~isempty(words_gt{index,z})
                % Compare every word in results_bottles with every word in
                % results_gt
                word_score(i,j,z-1) = EditDistance(words_bottles{i,j}, words_gt{index,z});
                z = z + 1;
            end
            % Detect best word score (minimum score) and add the result to
            % the other scores for words found in the same image
            [min_score, min_index] = min(word_score(i,j,:));
            if min_score < 100
                final_index(index,min_index) = final_index(min_index) + 1;
                matched_bottles(min_index) = j;
            end
            final_scores(j,min_index) = min_score;
            %disp(final_index)
            %disp(final_scores(j,:))
            j = j + 1;
        end
        % For all the words in words_gt corresponding to the minimum
        % scores found print the match in validation_results.txt
        for j = 1:col_gt-1
            match = words_gt{index,j+1};
            if isempty(match)
                continue;
            end
            [score,~] = min(final_scores(:,j));
            if score == 0
            	fprintf(fid, '\t%s found at position %i!\n', match, matched_bottles(j)-1);
                matches{i,m} = match;
                m = m + 1;
            elseif score <= 3 % change according to precision
                fprintf(fid, '\t%s found similar (score = %i).\n', match, score);
            else
                fprintf(fid, '\t%s not found (score > 3).\n', match);
            end
        end
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('New validation_results.txt!\n');

%% Determine where there is a match with a bottle

cmc = zeros(1,tot_bottles);
fid = fopen('matches.txt', 'w');
for i = 1:tot_bottles
    tot_matches = zeros(1,tot_gt);
    % Extract image name
    imgname = bottles_names{i};
    path = fileparts(which(imgname));
    gtname = split(path,'\');
    gtname = gtname{end};
    % Search for every word in results_bottles before the corrisponding bottle
    rank_score = zeros(1,tot_gt);
    for name = words_bottles(i,2:end) % for only perfect matches use '= matches(i)'
        if ~isempty(name)
            for j = 1:tot_gt
                if ~isempty(find(strcmp(words_gt(j,:),name)))
                    rank_score(j) = rank_score(j) + 1;
                end
            end
        end
    end
    % Get all matches
    for j = 1:length(rank_score)
        if rank_score(j) > 0
            tot_matches(j) = tot_matches(j) + 1; 
        end
    end
    % Extract and print best rank score
    [score,index] = max(rank_score);
    bottle = gt_names{index};
    if score > 0
        fprintf(fid, '%s in %s matches to %s bottle!\n', imgname, gtname, bottle);
    else
        fprintf(fid, '%s in %s doesn''t match with any bottle.\n', imgname, gtname);
    end
    
    % Draw plot 
    %figure;
    %x = 1:1:length(tot_matches);
    %scatter(x,tot_matches); % plot for displaying data distributions
    %xlim([0 18]);
    %ylim([0 2]);
    %xticks(0:1:17);
    %xticklabels(gt_names);
    %yticks(0:1);
    %grid on
    %xlabel('Bottles');
    %ylabel('Matches');
    
    % Calculate CMC
    if sum(tot_matches) ~= 0
        cmc(i) = sum(tot_matches);
    else
        cmc(i) = 8;
    end
end
fclose(fid);
fprintf('New matches.txt!\n');

% Plot CMC
figure('Name','CMC plot','NumberTitle','off')
plot(cmc);
xlim([0 18]);
ylim([0 9]);
xticks(0:1:17);
%xticklabels(bottles_names);
yticks(0:1:8);
grid on
xlabel('Bottles names');
ylabel('Matches');

% Calculate accurancy of the system (low score = high accurency)
auc = trapz(cmc)/tot_bottles;
fprintf('Accurancy is %.3f.\n', auc);

