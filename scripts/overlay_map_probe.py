exec(open('scripts/probe_map_sources.py').read().split("print('NAV'")[0])
from PIL import Image,ImageDraw
im=Image.open('artifacts/map-texture-probe.jpg');draw=ImageDraw.Draw(im)
for sec in d.sections:
 ids=d.point_sequence[sec.sequence_start:sec.sequence_start+sec.sequence_count]
 pts=[(512+d.points[i].x*.05,512-d.points[i].z*.05) for i in ids]
 if len(pts)>1:draw.line(pts,fill=(255,80,180),width=1)
im.save('artifacts/map-overlay-probe.jpg')
