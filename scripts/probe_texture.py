from PIL import Image
from pathlib import Path
import zipfile,struct,io
r=Path(r'D:\SteamLibrary\steamapps\common\ForzaHorizon6\media')
z=zipfile.ZipFile(r/'UI/Textures/Data_Bound/Map_Brio_Summer.zip')
b=z.read('0-0-0.swatchbin')
h=b'DDS '+struct.pack('<7I',124,0x81007,1024,1024,524288,0,1)+bytes(44)+struct.pack('<II4s5I',32,4,b'DXT1',0,0,0,0,0)+struct.pack('<5I',0x1000,0,0,0,0)
im=Image.open(io.BytesIO(h+b[140:])).convert('RGB')
im.save('artifacts/map-texture-probe.jpg')
print(len(z.namelist()),im.size)
