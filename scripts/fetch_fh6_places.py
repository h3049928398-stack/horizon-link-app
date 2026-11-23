"""Fetch public FH Hub marker coordinates; preserve provenance and fail on incomplete data.
Does not install dependencies or touch game files. Run explicitly to refresh the snapshot.
Projection calibration follows the MIT FH6 Scenic Navigator nav_logic.js; pending in-game verification.
"""
import json,math,re,html,urllib.request,hashlib,concurrent.futures,ssl
from pathlib import Path
from datetime import datetime,timezone
SSL_CONTEXT=ssl.create_default_context()
CATEGORIES=[["landmark","Landmark",75],["player-house","Player House",8],["car-meet","Car Meet",3],["drag-meet","Drag Meet",3],["day-trip","Day Trip",6],["drift-club-japan","Drift Club Japan",1],["moto-auto-zine","Moto Auto Zine",1],["food-delivery-job","Food Delivery Job",1],["festival-site","Festival Site",2],["horizon-event","Horizon Event",8],["danger-sign","Danger Sign",20],["drift-zone","Drift Zone",20],["speed-trap","Speed Trap",30],["trailblazer","Trailblazer Start Gate",11],["speed-zone","Speed Zone",30],["cross-country-event","Cross-Country Event",19],["road-racing-event","Road Racing Event",22],["street-racing-event","Street Racing Event",15],["dirt-racing-event","Dirt Racing Event",21],["touge-racing-event","Touge Racing Event",5],["time-attack","Time Attack",4],["drag-racing-event","Drag Racing Event",3],["barn-find","Barn Find",15],["treasure-car","Treasure Car",9],["bonus-board","Bonus Board",200],["aftermarket-car","Aftermarket Car",31],["photo-location","Photo Location",21],["curry","Curry Mascot",20],["dango","Dango Mascot",25],["edamame","Edamame Mascot",20],["kakigori","Kakigori Mascot",20],["matcha","Matcha Mascot",25],["omurice","Omurice Mascot",15],["onigiri","Onigiri Mascot",25],["ramen","Ramen Mascot",25],["tempura","Tempura Mascot",25],["trailblazer-finish","Trailblazer Finish",11]]
SPECIAL={'landmark':'地标','bonus-board':'广告牌','barn-find':'车房宝物','treasure-car':'秘藏座驾','player-house':'房屋','festival-site':'嘉年华','photo-location':'拍照点','car-meet':'车聚','drag-meet':'车聚'}
MASCOTS={'curry','dango','edamame','kakigori','matcha','omurice','onigiri','ramen','tempura'}
def category(slug):
 if slug in MASCOTS:return '吉祥物'
 if 'racing-event' in slug or slug in {'time-attack','horizon-event','cross-country-event'}:return '赛事'
 if slug in {'danger-sign','drift-zone','speed-trap','speed-zone','trailblazer','trailblazer-finish'}:return '特技'
 return SPECIAL.get(slug,'其他')
def world(lat,lng):
 ws=256*2**14
 px=(lng+180)/360*ws;py=(1-math.asinh(math.tan(lat*math.pi/180))/math.pi)/2*ws
 mx=(2086885-2089486)/(-7104.7695+119.49154)
 mz=(2089556-2087415)/(-1863.08-3888.595)
 bx=2089486-mx*(-119.49154);by=2087415-mz*3888.595
 return (px-bx)/mx,(py-by)/mz
def fetch(cat):
 slug,title,expected=cat;url='https://forzahorizonhub.com/map/'+slug
 cache=Path('artifacts/map_sources')/(slug+'.html');cache.parent.mkdir(exist_ok=True)
 if cache.is_file():raw=cache.read_bytes()
 else:
  req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
  with urllib.request.urlopen(req,timeout=15,context=SSL_CONTEXT) as r:raw=r.read()
  cache.write_bytes(raw)
 text=re.sub(r'<!--.*?-->','',raw.decode('utf8'),flags=re.S)
 rows=[]
 for card in re.findall(r'<li\b[^>]*>.*?</li>',text,re.S|re.I):
  name=re.search(r'<h[34][^>]*>(.*?)</h[34]>',card,re.S|re.I)
  link=re.search(r'href=["\x27]([^"\x27]*\bloc=(\d+)[^"\x27]*)["\x27]',card,re.I)
  plain=html.unescape(re.sub('<[^>]*>',' ',card))
  coordinate=re.search(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)',plain)
  if not(name and link and coordinate):continue
  lat=float(coordinate[1]);lng=float(coordinate[2]);x,z=world(lat,lng)
  if not(-11000<x<11000 and -12000<z<12000):raise ValueError(f'{slug}: coordinate outside game bounds')
  rows.append({'id':'hub.'+link[2],'name':html.unescape(re.sub('<[^>]+>','',name[1])).strip(),'category':category(slug),'x':x,'z':z,'quality':'community','note':'公开地图坐标 · 待游戏实测','latitude':lat,'longitude':lng,'sources':[{'url':html.unescape('https://forzahorizonhub.com'+link[1]),'category_url':url,'provider':'Forza Horizon Hub','retrieved_at':datetime.fromtimestamp(cache.stat().st_mtime,timezone.utc).date().isoformat()}]})
 if len(rows)!=expected:raise ValueError(f'{slug}: expected {expected}, parsed {len(rows)}')
 return rows,{'url':url,'sha256':hashlib.sha256(raw).hexdigest(),'count':len(rows)}
def main():
 rows=[];sources=[];errors=[]
 def save():
  unique={p['id']:p for p in rows}
  Path('artifacts/hub-coordinate-source.json').write_text(json.dumps({'sources':sources,'errors':errors,'places':list(unique.values())},ensure_ascii=False,indent=2),encoding='utf8')
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
  jobs={ex.submit(fetch,c):c[0] for c in CATEGORIES}
  for job in concurrent.futures.as_completed(jobs):
   try:
    result=job.result();rows.extend(result[0]);sources.append(result[1]);print(jobs[job],len(result[0]),flush=True)
   except Exception as e:errors.append(str(e));print(jobs[job],str(e),flush=True)
   save()
 unique={p['id']:p for p in rows}
 target=Path('artifacts/hub-coordinate-source.json')
 target.write_text(json.dumps({'sources':sources,'errors':errors,'places':list(unique.values())},ensure_ascii=False,indent=2),encoding='utf8')
 print(json.dumps({'markers':len(unique),'sourceRows':len(rows),'categories':{c:sum(p['category']==c for p in unique.values()) for c in sorted({p['category'] for p in unique.values()})}},ensure_ascii=False))
if __name__=='__main__':main()

