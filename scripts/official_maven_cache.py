"""Loopback-only official Maven cache, using persistent Windows HTTPS clients."""
import atexit,hashlib,http.server,json,os,pathlib,queue,shutil,subprocess,threading,time,urllib.parse
ROOT=pathlib.Path(__file__).resolve().parents[1]
CACHE=ROOT/'.tools/official-maven-cache';CACHE.mkdir(parents=True,exist_ok=True)
BASES={'plugins':'https://plugins.gradle.org/m2/','central':'https://repo.maven.apache.org/maven2/','google':'https://dl.google.com/dl/android/maven2/','flutter':'https://storage.googleapis.com/download.flutter.io/'}
LOCKS={};LOCK=threading.Lock()
PWSH=pathlib.Path(r'C:\Users\30499\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe')
if not PWSH.is_file():PWSH=pathlib.Path(shutil.which('pwsh.exe') or shutil.which('powershell.exe'))
class Backend:
 def __init__(self):
  self.process=subprocess.Popen([str(PWSH),'-NoLogo','-NoProfile','-File',str(ROOT/'scripts/maven_windows_fetch.ps1')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=(ROOT/'artifacts/maven-windows-fetch.log').open('a',encoding='utf8'),text=True,encoding='utf8',bufsize=1,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
 def fetch(self,url,target):
  self.process.stdin.write(json.dumps({'url':url,'path':str(target)})+'\n');self.process.stdin.flush()
  line=self.process.stdout.readline()
  if not line:raise RuntimeError('Windows download client stopped')
  return json.loads(line)
 def close(self):
  if self.process.poll() is None:self.process.terminate()
BACKENDS=queue.Queue();CLIENTS=[Backend(),Backend()]
for client in CLIENTS:BACKENDS.put(client)
atexit.register(lambda:[client.close() for client in CLIENTS])
def checksum(path,algorithm):
 h=hashlib.new(algorithm)
 with path.open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
class Handler(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def log_message(self,*args):pass
 def handle(self):
  try:super().handle()
  except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
 def do_HEAD(self):self.respond(False)
 def do_GET(self):self.respond(True)
 def respond(self,body):
  if self.path=='/health':
   data=b'horizon-official-maven-cache-v1';self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers()
   if body:self.wfile.write(data)
   return
  parts=urllib.parse.unquote(urllib.parse.urlsplit(self.path).path).lstrip('/').split('/')
  if len(parts)<2 or parts[0] not in BASES or any(p in {'.','..',''} or ':' in p or '\\' in p for p in parts):self.send_error(400);return
  role=parts[0];relative='/'.join(parts[1:]);url=BASES[role]+urllib.parse.quote(relative,safe='/@+.-_')
  target=CACHE.joinpath(*parts).resolve()
  if CACHE.resolve() not in target.parents:self.send_error(400);return
  target.parent.mkdir(parents=True,exist_ok=True)
  missing=target.with_name(target.name+'.not-found')
  with LOCK:mutex=LOCKS.setdefault(str(target),threading.Lock())
  with mutex:
   if not target.is_file():
    for other in BASES:
     source=CACHE.joinpath(other,*parts[1:])
     if source.is_file():
      shutil.copyfile(source,target)
      if missing.exists():missing.unlink()
      break
   if target.suffix in {'.sha1','.sha256','.sha512'} and not target.exists():
    base=target.with_suffix('')
    if base.is_file():target.write_text(checksum(base,target.suffix[1:]),encoding='ascii')
   if not target.is_file() and missing.is_file():self.send_error(404);return
   if not target.is_file():
    # Gradle plugin markers are POM-only modules.
    if relative.endswith('.jar') and len(parts)>3 and parts[-3].endswith('.gradle.plugin'):
     missing.write_text('404');self.send_error(404);return
    temp=target.with_name(target.name+'.download');result={'code':0,'error':''}
    for attempt in range(3):
     client=BACKENDS.get()
     try:result=client.fetch(url,temp)
     except Exception as e:result={'code':0,'error':str(e)}
     finally:BACKENDS.put(client)
     if result['code'] in {200,404,410}:break
     time.sleep(1)
    if result['code'] in {404,410}:missing.write_text('404');self.send_error(404);return
    if result['code']!=200:
     print('Upstream download failed',url,result.get('error',''),flush=True);self.send_error(502);return
    temp.replace(target)
    print('Cached',role,relative,target.stat().st_size,flush=True)
  self.send_response(200);self.send_header('Content-Length',str(target.stat().st_size));self.send_header('Content-Type','application/octet-stream');self.end_headers()
  if body:
   with target.open('rb') as f:
    for data in iter(lambda:f.read(256*1024),b''):self.wfile.write(data)
if __name__=='__main__':
 print('Horizon official Maven cache on 127.0.0.1:18765 (persistent Windows HTTPS)',flush=True)
 http.server.ThreadingHTTPServer(('127.0.0.1',18765),Handler).serve_forever()

