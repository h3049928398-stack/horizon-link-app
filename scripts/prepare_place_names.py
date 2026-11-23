"""Build a small bilingual name overlay; leave source coordinates untouched."""
import hashlib
import json
from pathlib import Path
import zipfile

from extract_fh6_place_names import normalize, parse_str

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r'D:\SteamLibrary\steamapps\common\ForzaHorizon6\media\Stripped\StringTables')
PRIORITY = {
    '地标': ['Landmarks'], '房屋': ['PlayerHouse'],
    '赛事': ['CareerTrackInfo', 'CareerRace', 'CareerRaceCollection', 'TimeAttack', 'Map', 'InitialExperience'],
    '特技': ['DangerSign', 'SpeedTrap', 'SpeedZone', 'DriftZone', 'Trailblazer', 'DragEvent', 'DriftAttack', 'TimeAttack'],
    '车聚': ['CarMeets', 'DragEvent', 'Map'], '吉祥物': ['Map'],
    '嘉年华': ['Landmarks'], '拍照点': ['Landmarks', 'ChallengeData'],
    '其他': ['HorizonStoryData', 'Map'],
}
# Explicit spelling/short-name aliases, reviewed against game strings.
ALIASES = {
    'Irokawa Space Centre': 'Irokawa Space Center',
    'Kawazu Nandaru Loop Bridge': 'Kawazu Nanadaru Loop Bridge',
    'Festival Kilometre': 'Festival Kilometer',
    'Curry': 'Curry Rice', 'Matcha': 'Matcha Tea',
    'Legend Island Festival Site': 'Horizon Legend Island Festival Site',
    'Meiji Jingu Gaien Ginkgo Avenue': 'Meiji Jingu Gaien Gingko Avenue',
    'Tokyo Central Railway Station': 'Tokyo Railway Station',
    'Tokyo Central Railway Station Cut Through': 'Tokyo Railway Station Cut Through',
}


def main():
    tables = {}
    for lang in ['CHS', 'EN']:
        with zipfile.ZipFile(SOURCE / (lang + '.zip')) as archive:
            tables[lang] = {Path(n).stem: parse_str(archive.read(n))
                            for n in archive.namelist() if n.endswith('.str')}
    places = json.loads((ROOT / 'flutter_app/assets/map/places.json').read_text(encoding='utf-8'))
    output = {}
    for p in places:
        name = ALIASES.get(p['name'], p['name'])
        for table in PRIORITY.get(p['category'], []):
            hits = []
            for key, (_, en) in tables['EN'][table].items():
                if normalize(en) != normalize(name):
                    continue
                # Restrict broad UI/challenge tables to the relevant name keys.
                if table == 'Map' and not (key.startswith('IDS_RegionalMascot_') or
                    key in ['IDS_AftermarketCar_SubTitle', 'IDS_MapPin_InitialDrive_Title']):
                    continue
                if table == 'ChallengeData' and not key.startswith('IDS_Name_'):
                    continue
                if table == 'CareerTrackInfo' and not key.startswith('IDS_DisplayName_'):
                    continue
                if table == 'Landmarks' and not key.startswith('IDS_Area_Discovered_'):
                    continue
                if table == 'PlayerHouse' and not key.startswith('IDS_DisplayName_'):
                    continue
                zh = tables['CHS'][table][key][1].strip()
                if zh and '<' not in zh:
                    hits.append((key, zh))
            if hits and len({zh for _, zh in hits}) == 1:
                output[p['id']] = {'zh': hits[0][1], 'en': p['name'],
                    'source': {'table': table, 'keys': [k for k, _ in hits],
                               'matchedEnglish': name, 'alias': name != p['name']}}
                break
        if p['category'] == '广告牌':
            # A generic UI label, not an invented unique official location name.
            zh = p['name'].replace('Bonus Board', '奖励广告牌')
            output[p['id']] = {'zh': zh, 'en': p['name'], 'source': {'kind': 'generic_label'}}
        elif p['category'] == '赛道':
            output[p['id']] = {'zh': p['name'], 'en': 'Track geometry start ' + p['id'],
                               'source': {'kind': 'geometry_label'}}
    target = ROOT / 'flutter_app/assets/map/place_names.json'
    payload = {'version': 1, 'sources': {lang: hashlib.sha256((SOURCE / (lang + '.zip')).read_bytes()).hexdigest()
               for lang in tables}, 'names': output}
    target.write_text(json.dumps(payload, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    print('Named records:', len(output), '/', len(places))
    print('Game name matches:', sum('table' in r['source'] for r in output.values()))
    print('Unmatched:', [(p['category'], p['name']) for p in places if p['id'] not in output])


if __name__ == '__main__':
    main()
