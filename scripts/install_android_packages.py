"""Install selected official Android packages, verifying repository checksums.
Only writes to the configured development SDK. Does not change system PATH.
"""
import concurrent.futures,hashlib,json,pathlib,subprocess,zipfile,xml.etree.ElementTree as ET,sys
from xml.dom import minidom
ROOT=pathlib.Path(__file__).resolve().parents[1]
SDK=pathlib.Path(r'C:\Users\30499\.codex\visualizations\2026\10\26\01a178ad-e9b5-7d92-9669-57e4fec3e57f\sdk\android')
DOWNLOADS=ROOT/'.tools/downloads'
WANTED={'platforms;android-35','platforms;android-36','build-tools;36.0.0','ndk;28.2.13676358','cmake;3.22.1'}
def download(url,target,size):
 # This connection supports ranged responses reliably; verify each piece and the final archive.
 piece=4*1024*1024;parts=target.parent/(target.name+'.parts');parts.mkdir(exist_ok=True)
 def fetch(index):
  start=index*piece;end=min(size,start+piece)-1;path=parts/f'{index:05d}.part'
  expected=end-start+1
  if not path.is_file() or path.stat().st_size!=expected:
   subprocess.run(['curl.exe','--fail','--location','--silent','--show-error','--http1.1','--range',f'{start}-{end}','--retry','2','--retry-all-errors','--retry-delay','1','--connect-timeout','8','--max-time','90','--output',str(path),url],check=True)
  if path.stat().st_size!=expected:raise ValueError(f'Unexpected range response: {url} piece {index}')
  return path
 count=(size+piece-1)//piece;completed=0
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  jobs=[pool.submit(fetch,i) for i in range(count)]
  for job in concurrent.futures.as_completed(jobs):
   job.result();completed+=1
   if completed%12==0 or completed==count:print(target.name,f'{completed}/{count} parts',flush=True)
 with target.open('wb') as out:
  for i in range(count):
   with (parts/f'{i:05d}.part').open('rb') as f:
    for block in iter(lambda:f.read(1024*1024),b''):out.write(block)
def digest(path,algorithm):
 h=hashlib.new(algorithm)
 with path.open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
def metadata(package,destination):
 original=minidom.parse(str(DOWNLOADS/'android-repository.xml'))
 raw=next(n for n in original.getElementsByTagName('remotePackage') if n.getAttribute('path')==package)
 doc=minidom.Document();common='http://schemas.android.com/repository/android/common/02'
 root=doc.createElementNS(common,'localRepo:repository');doc.appendChild(root)
 root.setAttribute('xmlns:localRepo',common)
 for i in range(original.documentElement.attributes.length):
  a=original.documentElement.attributes.item(i)
  if a.name.startswith('xmlns'):root.setAttribute(a.name,a.value)
 for license in original.documentElement.childNodes:
  if license.nodeType==license.ELEMENT_NODE and license.tagName=='license':root.appendChild(doc.importNode(license,True))
 local=doc.createElement('localPackage');local.setAttribute('path',package);local.setAttribute('obsolete','false')
 for child in raw.childNodes:
  if child.nodeType==child.ELEMENT_NODE and child.tagName in {'type-details','revision','display-name','uses-license','dependencies'}:
   local.appendChild(doc.importNode(child,True))
 root.appendChild(local)
 (destination/'package.xml').write_bytes(doc.toxml(encoding='utf-8'))
def install(record):
 package,url,size,algorithm,checksum=record
 destination=SDK.joinpath(*package.split(';'))
 previous=ROOT/'artifacts/android-sdk-installation.json'
 if previous.is_file() and (destination/'package.xml').is_file() and (destination/'source.properties').is_file():
  for installed in json.loads(previous.read_text(encoding='utf8')):
   if installed['package']==package and installed['repositoryChecksum']==checksum:
    print('Already verified',package,flush=True);return installed
 archive=DOWNLOADS/url
 print('Preparing',package,round(size/1024/1024),'MiB',flush=True)
 if not archive.is_file() or archive.stat().st_size!=size or digest(archive,algorithm)!=checksum:
  if '--offline' in sys.argv:raise ValueError('Verified archive is missing. Run scripts/install_android_sdk.ps1: '+url)
  download('https://dl.google.com/android/repository/'+url,archive,size)
 if archive.stat().st_size!=size or digest(archive,algorithm)!=checksum:raise ValueError('Checksum mismatch: '+url)
 destination.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(archive) as z:
  files=[i for i in z.infolist() if not i.is_dir()]
  prefixes={pathlib.PurePosixPath(i.filename).parts[0] for i in files}
  strip=1
  if len(prefixes)!=1:
   if not package.startswith('cmake;'):raise ValueError('Unexpected archive roots: '+str(prefixes))
   strip=0
  for item in files:
   rel=pathlib.PurePosixPath(item.filename)
   if rel.is_absolute() or '..' in rel.parts or any(':' in p for p in rel.parts):raise ValueError('Unsafe archive entry')
   target=destination.joinpath(*rel.parts[strip:]).resolve()
   if destination.resolve() not in target.parents:raise ValueError('Archive entry escaped SDK')
   target.parent.mkdir(parents=True,exist_ok=True)
   target.write_bytes(z.read(item))
 metadata(package,destination)
 print('Installed and verified',package,flush=True)
 return {'package':package,'url':'https://dl.google.com/android/repository/'+url,'sha256':digest(archive,'sha256'),'repositoryChecksum':checksum,'bytes':size}
def main():
 root=ET.parse(DOWNLOADS/'android-repository.xml').getroot();records=[]
 for p in root.findall('remotePackage'):
  if p.get('path') not in WANTED:continue
  for a in p.findall('archives/archive'):
   if a.findtext('host-os') not in {None,'windows'}:continue
   c=a.find('complete');check=c.find('checksum')
   records.append((p.get('path'),c.findtext('url'),int(c.findtext('size')),check.get('type'),check.text))
 if {r[0] for r in records}!=WANTED:raise ValueError('Official repository is missing required packages')
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:report=list(pool.map(install,records))
 (ROOT/'artifacts/android-sdk-installation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
 print('Android SDK packages ready',flush=True)
if __name__=='__main__':main()

