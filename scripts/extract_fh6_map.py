"""Read installed FH6 WVAN roads and BC1 map tiles. Never writes to the game.

WVAN parser: scripts/vendor/fh6_nav (MIT; see bundled LICENSE).
Basemap alignment is image-derived, independently of navigation geometry.
"""
import argparse, json, sys, struct, zipfile, io, hashlib
from pathlib import Path
from PIL import Image,ImageChops,ImageStat
sys.path.insert(0,str(Path(__file__).parent/'vendor'))
from fh6_nav.wvan import parse_wvan_file
from fh6_nav.graph import build_graph
from fh6_nav.compiler import compile_graph_dict

def texture(b):
 if b[:4]!=b'burG' or len(b)!=524428:raise ValueError('Unsupported map texture')
 h=b'DDS '+struct.pack('<7I',124,0x81007,1024,1024,524288,0,1)+bytes(44)+struct.pack('<II4s5I',32,4,b'DXT1',0,0,0,0,0)+struct.pack('<5I',0x1000,0,0,0,0)
 return Image.open(io.BytesIO(h+b[140:])).convert('RGB')

def extract(root,out):
 out.mkdir(parents=True,exist_ok=True)
 source=root/'OpenWorld/Brio/Freeroam/Brio_00.nav'
 doc=parse_wvan_file(source); graph=build_graph(doc)
 data=compile_graph_dict(graph)
 data['capabilities']['route_validated']=False # App routes require on-device validation.
 data['sections']=[{'road':dict(doc.section_metadata[s.id].values).get('road_type',''),'name':dict(doc.section_metadata[s.id].values).get('display_name',''),'tunnel':dict(doc.section_metadata[s.id].values).get('is_tunnel')=='true'} for s in doc.sections]
 data['mapTransform']={'scale':.046504,'tx':582.896,'ty':499.376,'quality':'image-derived'}
 # Only explicit sequence topology is retained; no proximity links at flyovers.
 (out/'navgraph.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
 texture_checks={}
 for season in ['Summer','Winter','Spring','Autumn']:
  path=root/f'UI/Textures/Data_Bound/Map_Brio_{season}.zip'
  z=zipfile.ZipFile(path)
  # Four original level-1 tiles -> 2048px overview, readable when zooming.
  im=Image.new('RGB',(2048,2048))
  for x in range(2):
   for y in range(2):im.paste(texture(z.read(f'1-{y}-{x}.swatchbin')),(x*1024,y*1024))
  error=sum(ImageStat.Stat(ImageChops.difference(im.resize((1024,1024)),texture(z.read('0-0-0.swatchbin')))).mean)/3
  if error>15:raise ValueError(f'{season}: tile assembly disagrees with game overview ({error})')
  texture_checks[season]=round(error,3)
  im.save(out/f'map_{season.lower()}.jpg',quality=88,optimize=True)
 # Keep true race route geometry anchors; do not call them the event trigger.
 places=[]; failures=[]
 for path in sorted((root/'OpenWorld/Brio/AITracks').glob('Route*.nav')):
  try:
   route=parse_wvan_file(path)
   ids=route.point_sequence
   if not ids:continue
   p=route.points[ids[0]]
   places.append({'id':path.stem,'name':f'赛道入口 {path.stem}','category':'赛道','x':p.x,'y':p.y,'z':p.z,'quality':'route_geometry','note':'游戏赛道几何起点，赛事触发点待实测'})
  except Exception as e:failures.append({'file':path.name,'error':str(e)})
 race_count=len(places)
 public=Path('artifacts/hub-coordinate-source.json')
 community=Path('artifacts/community-coordinate-source.json')
 if public.is_file():
  public_places=json.loads(public.read_text(encoding='utf-8'))['places']
  for p in public_places:
   if any(s.get('category_url','').endswith('/cross-country-event') for s in p.get('sources',[])):p['category']='赛事'
   near=min(doc.points,key=lambda q:(q.x-p['x'])**2+(q.z-p['z'])**2)
   p['y']=near.y # Source has no altitude; only approximate the road approach height.
   p['altitude_source']='nearest_road'
   p['road_distance_m']=round(((near.x-p['x'])**2+(near.z-p['z'])**2)**.5,2)
  places.extend(public_places)
 if community.is_file():
  present={p['category'] for p in places}
  places.extend(p for p in json.loads(community.read_text(encoding='utf-8')) if p['category'] not in present)
 (out/'places.json').write_text(json.dumps(places,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
 report={'source':str(source),'sha256':doc.source_sha256,'stats':data['stats'],'raceGeometryAnchors':race_count,'communityPlaces':len(places)-race_count,'raceParseFailures':failures,'basemapTransform':data['mapTransform'],'tileOverviewMeanError':texture_checks,'limitations':['Not the game executable navigation engine','Image-derived basemap alignment','Event trigger and collection state not extracted']}
 Path('artifacts/map-extraction.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--media',type=Path,default=Path(r'D:\SteamLibrary\steamapps\common\ForzaHorizon6\media'));p.add_argument('--out',type=Path,default=Path('flutter_app/assets/map'));a=p.parse_args();extract(a.media,a.out)
