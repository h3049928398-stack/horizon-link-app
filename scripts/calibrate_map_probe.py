exec(open('scripts/probe_map_sources.py').read().split("print('NAV'")[0])
import numpy as np
from PIL import Image,ImageFilter,ImageDraw
im=Image.open('artifacts/map-texture-probe.jpg').convert('RGB')
gray=im.convert('L'); a=np.asarray(gray,dtype=float); blur=np.asarray(gray.filter(ImageFilter.GaussianBlur(3)),dtype=float)
signal=np.clip(a-blur,-20,40)
# Rural low-altitude roads, excluding snow and the dense city buildings.
pts=np.array([(p.x,p.z) for p in d.points if p.y<300 and p.z>-2500])[::3]
def score(s,tx,ty):
 xx=np.rint(pts[:,0]*s+tx).astype(int);yy=np.rint(-pts[:,1]*s+ty).astype(int)
 mask=(xx>=2)&(yy>=2)&(xx<1022)&(yy<1022)
 return signal[yy[mask],xx[mask]].mean()
best=(-1e9,0,0,0)
for s in np.arange(.035,.056,.001):
 for tx in range(470,651,8):
  for ty in range(450,571,8):
   v=score(s,tx,ty)
   if v>best[0]:best=(v,s,tx,ty)
print('COARSE',best)
for step in [.0002,.00004,.000008]:
 _,ss,xx,yy=best
 for s in np.arange(ss-step*5,ss+step*5.1,step):
  for tx in np.arange(xx-step*20000,xx+step*20001,step*4000):
   for ty in np.arange(yy-step*20000,yy+step*20001,step*4000):
    v=score(s,tx,ty)
    if v>best[0]:best=(v,s,tx,ty)
 print('FINE',best)
_,s,tx,ty=best
draw=ImageDraw.Draw(im)
for sec in d.sections:
 ids=d.point_sequence[sec.sequence_start:sec.sequence_start+sec.sequence_count]
 path=[(tx+d.points[i].x*s,ty-d.points[i].z*s) for i in ids]
 if len(path)>1:draw.line(path,fill=(255,80,180),width=1)
im.save('artifacts/map-calibrated-probe.jpg')
