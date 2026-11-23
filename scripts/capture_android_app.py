"""Capture only this app, refusing screenshots of other foreground applications."""
import argparse,pathlib,subprocess,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
ADB=pathlib.Path(r'C:\Users\30499\.codex\visualizations\2026\10\26\01a178ad-e9b5-7d92-9669-57e4fec3e57f\sdk\android\platform-tools\adb.exe')
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--name',default='screen');a=p.parse_args()
if not re.fullmatch('[a-z0-9_-]+',a.name):raise ValueError('Invalid capture name')
command=[str(ADB),'-s',a.device]
focus=subprocess.check_output(command+['shell','dumpsys window | grep mCurrentFocus'],text=True,encoding='utf8',errors='replace')
if 'com.horizonlink.horizon_link/' not in focus:raise SystemExit('Open Horizon Link and unlock the phone before capturing. No screenshot was taken.')
target=ROOT/'artifacts'/f'android-{a.name}.png'
with target.open('wb') as f:subprocess.run(command+['exec-out','screencap','-p'],stdout=f,check=True)
pid=subprocess.check_output(command+['shell','pidof','com.horizonlink.horizon_link'],text=True).strip().split()[0]
logs=subprocess.check_output(command+['logcat','-d','-t','600','--pid='+pid],encoding='utf8',errors='replace')
(ROOT/'artifacts'/f'android-{a.name}.log').write_text(logs,encoding='utf8')
print('Saved own-app screenshot and process log:',target)
