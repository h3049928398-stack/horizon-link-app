"""Reuse integrity-checked artifacts already present in this project's Gradle cache."""
import hashlib,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCE=pathlib.Path(r'C:\Users\30499\.codex\visualizations\2026\10\26\01a178ad-e9b5-7d92-9669-57e4fec3e57f\sdk\gradle-cache\caches\modules-2\files-2.1')
TARGET=ROOT/'.tools/official-maven-cache'
count=0
for source in SOURCE.glob('*/*/*/*/*'):
 if not source.is_file() or source.suffix not in {'.pom','.module','.jar','.aar'}:continue
 group,artifact,version,digest,filename=source.relative_to(SOURCE).parts
 data=source.read_bytes()
 if hashlib.sha1(data).hexdigest()!=digest:continue
 relative=pathlib.Path(*group.split('.'))/artifact/version/filename
 for role in ['plugins','central','google','flutter']:
  target=TARGET/role/relative;target.parent.mkdir(parents=True,exist_ok=True)
  if not target.exists():target.write_bytes(data)
  negative=target.with_name(target.name+'.not-found')
  if negative.exists():negative.unlink()
  for algorithm in ['sha1','sha256','sha512']:
   checksum=target.with_name(target.name+'.'+algorithm)
   if not checksum.exists():checksum.write_text(hashlib.new(algorithm,data).hexdigest(),encoding='ascii')
 count+=1
print('Reused verified Gradle cache artifacts:',count)

