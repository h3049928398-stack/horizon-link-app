import sys, collections, sqlite3, zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'vendor'))
from fh6_nav.wvan import parse_wvan_file
root=Path(r'D:\SteamLibrary\steamapps\common\ForzaHorizon6\media')
d=parse_wvan_file(root/'OpenWorld/Brio/Freeroam/Brio_00.nav')
print('NAV',len(d.points),len(d.sections),d.source_sha256)
print('KEYS',d.metadata_keys)
print('BOUNDS',[(k,min(getattr(p,k) for p in d.points),max(getattr(p,k) for p in d.points)) for k in ['x','y','z']])
print('VALUES',d.metadata_values[:100])
p=root/'Stripped/gamedbRC.slt'
print('DB HEADER',p.open('rb').read(32))
if p.open('rb').read(16)==b'SQLite format 3\x00':
 c=sqlite3.connect(p.as_uri()+'?mode=ro',uri=True)
 tables=[r[0] for r in c.execute("select name from sqlite_master where type='table'")]
 print('TABLES',tables)
for name in ['Map_Brio_Summer.zip','Map_Brio_Winter.zip']:
 z=zipfile.ZipFile(root/'UI/Textures/Data_Bound'/name)
 print(name,[(i.filename,i.file_size) for i in z.infolist()][:10])
 i=z.infolist()[0];print('TEXTURE HEADER',z.read(i)[:160].hex())
