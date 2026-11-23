"""Build redistributable OFL fonts offline. See docs/FONT_LICENSES.md."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'flutter_app/assets'
CACHE = ROOT / '.tools/font-sources'
MANIFEST = ROOT / 'scripts/font_sources.json'
GAIN_TEXT = '名次提升POSITION GAINED'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def source_files():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    sources = {}
    for entry in manifest['files']:
        path = CACHE / entry['file']
        if not path.exists():
            raise RuntimeError('Missing font source. Run scripts/fetch_font_sources.ps1 first: ' + str(path))
        data = path.read_bytes()
        if sha256(data) != entry['sha256']:
            raise RuntimeError('Font source checksum mismatch: ' + str(path))
        sources[entry['file']] = data
    return manifest, sources


def app_characters():
    text = ''.join(p.read_text(encoding='utf-8') for p in sorted((ROOT / 'flutter_app/lib').rglob('*.dart')))
    escapes = re.findall(r'\\u(?:\{([0-9a-fA-F]{1,6})\}|([0-9a-fA-F]{4}))', text)
    text += ''.join(chr(int(braced or short, 16)) for braced, short in escapes)
    for path in sorted((ASSETS / 'map').glob('*.json')):
        text += json.dumps(json.loads(path.read_text(encoding='utf-8')), ensure_ascii=False)
    return set(text + ''.join(chr(i) for i in range(32, 127)))


def build_font(source, family, weight, characters):
    font = TTFont(io.BytesIO(source), recalcTimestamp=False)
    if characters is not None:
        cmap = font.getBestCmap()
        required = {ord(c) for c in characters if c.isprintable()}
        missing = required - cmap.keys()
        if missing:
            raise RuntimeError('Missing required glyphs: ' + ', '.join(f'U+{c:04X}' for c in sorted(missing)))
        options = subset.Options()
        options.recalc_bounds = True
        options.recalc_timestamp = False
        options.name_IDs = ['*']
        options.name_languages = ['*']
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes={ord(c) for c in characters} & cmap.keys())
        subsetter.subset(font)
    if 'fvar' in font:
        instantiateVariableFont(font, {'wght': weight}, inplace=True)
    # Distinct derivative names; preserve copyright and full OFL metadata.
    names = font['name']
    names.names = [n for n in names.names if n.nameID not in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25)]
    values = {1: family, 2: 'Regular', 3: family.replace(' ', '') + '-1.0', 4: family,
              6: family.replace(' ', ''), 16: family, 17: 'Regular'}
    for name_id, value in values.items():
        names.setName(value, name_id, 3, 1, 0x409)
    font['OS/2'].usWeightClass = weight
    font.recalcTimestamp = False
    result = io.BytesIO()
    font.save(result)
    return result.getvalue()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=['all', 'gain'], default='all')
    args = parser.parse_args(argv)
    manifest, sources = source_files()
    specs = [
        ('chinese.ttf', 'NotoSansSC.ttf', 'Horizon Link Sans', 400, app_characters()),
        ('gain_label.ttf', 'NotoSansSC.ttf', 'Horizon Link Gain', 700, set(GAIN_TEXT)),
        ('dashboard.ttf', 'BarlowCondensed-SemiBold.ttf', 'Horizon Link Dashboard', 600, None),
    ]
    outputs = {}
    for target, source, family, weight, characters in specs:
        if args.only == 'gain' and target != 'gain_label.ttf':
            continue
        outputs[target] = build_font(sources[source], family, weight, characters)
    # Build everything successfully before replacing any shipped asset.
    for filename, data in outputs.items():
        path = ASSETS / filename
        if not path.exists() or path.read_bytes() != data:
            temp = path.with_suffix('.ttf.tmp')
            temp.write_bytes(data)
            temp.replace(path)
        print(f'{filename}: {len(data)} bytes, SHA256 {sha256(data)}')
    for filename in ('NotoSansSC-OFL.txt', 'BarlowCondensed-OFL.txt'):
        target = ASSETS / 'licenses' / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(sources[filename])
    report = {
        'upstream_revision': manifest['revision'],
        'fonttools': fontTools.__version__,
        'fonts': {name: {'sha256': sha256((ASSETS / name).read_bytes()), 'source': source,
                         'family': family, 'weight': weight}
                  for name, source, family, weight, _ in specs},
    }
    (ASSETS / 'licenses/font-build.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
