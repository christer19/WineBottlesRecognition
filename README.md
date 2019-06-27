# WineBottlesRecognition

## How to add new images to the dataset?

Inside *__images_winebottles__*:

- add the _ground-truth image_ of your bottle of wine (if not already present) in the directory *__gt__*
- add all the _other images_ in the directory *__raw__* and inside another directory named as the bottle to recognize

## How to recognize a chosen bottle?

- Run __recognition.py__ followed by the name of the image:
  - `python recognition.py`

- Look for the results (in the same directory of the image) in the __*image_name*.json__ file. The first result is the name of the bottle. 

## How accurate is the result?

- Run __validation.py__ to find out:
  - `python validation.py`
 
- The accurancy value is printed at the end
