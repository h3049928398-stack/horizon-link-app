"""Prepare the official, checksum-verified Gradle runtime in the wrapper cache."""
import hashlib,pathlib,zipfile
root=pathlib.Path(__file__).resolve().parents[1]
sdk=pathlib.Path(r'C:\Users\30499\.codex\visualizations\2026\10\26\01a178ad-e9b5-7d92-9669-57e4fec3e57f\sdk')
archive=root/'.tools/downloads/gradle-9.3.1-all.zip'
expected=(root/'.tools/downloads/gradle-9.3.1-all.zip.sha256').read_text().strip()
h=hashlib.sha256()
with archive.open('rb') as f:
 for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
if h.hexdigest()!=expected:raise ValueError('Gradle checksum mismatch')
url='https://services.gradle.org/distributions/gradle-9.3.1-all.zip'
number=int.from_bytes(hashlib.md5(url.encode()).digest(),'big');digits='0123456789abcdefghijklmnopqrstuvwxyz';key=''
while number:key=digits[number%36]+key;number//=36
cache=sdk/'gradle-cache/wrapper/dists/gradle-9.3.1-all'/key
cache.mkdir(parents=True,exist_ok=True)
count=0
with zipfile.ZipFile(archive) as z:
 for item in z.infolist():
  p=pathlib.PurePosixPath(item.filename)
  if item.is_dir() or len(p.parts)<2:continue
  # Docs and sources are optional. Keep all runtime libraries and notices.
  if len(p.parts)>2 and p.parts[1] not in {'bin','lib','init.d'}:continue
  target=cache.joinpath(*p.parts).resolve()
  if cache.resolve() not in target.parents:raise ValueError('Archive path escaped Gradle cache')
  target.parent.mkdir(parents=True,exist_ok=True)
  target.write_bytes(z.read(item));count+=1
(cache/'gradle-9.3.1-all.zip.ok').touch()
print('Verified Gradle runtime prepared:',count,'files',flush=True)
