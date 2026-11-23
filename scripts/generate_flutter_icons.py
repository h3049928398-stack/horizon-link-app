"""Draw the original app mark directly into Flutter launcher assets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

project=Path(__file__).resolve().parents[1]/'flutter_app'
def icon(size):
    image=Image.new('RGB',(size*4,size*4),(192,243,91))
    draw=ImageDraw.Draw(image)
    for shape in [[(15,47),(27,16),(37,16),(25,47)],[(36,47),(43,29),(50,29),(43,47)]]:
        draw.polygon([(x*size/64*4,y*size/64*4) for x,y in shape],fill=(20,25,18))
    return image.resize((size,size),Image.Resampling.LANCZOS)

for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    icon(size).save(project/f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
directory=project/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((directory/'Contents.json').read_text())['images']:
    if 'filename' in entry:
        size=round(float(entry['size'].split('x')[0])*float(entry.get('scale','1x')[:-1]))
        icon(size).save(directory/entry['filename'])
for size in [192,512]:
    for name in [f'Icon-{size}.png',f'Icon-maskable-{size}.png']:
        icon(size).save(project/'web/icons'/name)
icon(64).save(project/'web/favicon.png')
print('Generated Flutter Android, iOS and preview icons.')
