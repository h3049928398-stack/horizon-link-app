"""Audit shipped font identity, license bytes, hashes and required glyph coverage."""
import json

from fontTools.ttLib import TTFont

from prepare_flutter_fonts import ASSETS, GAIN_TEXT, app_characters, sha256, source_files


def main():
    _, sources = source_files()
    report = json.loads((ASSETS / 'licenses/font-build.json').read_text(encoding='utf-8'))
    assert set(report['fonts']) == {p.name for p in ASSETS.glob('*.ttf')}
    for filename, entry in report['fonts'].items():
        path = ASSETS / filename
        assert sha256(path.read_bytes()) == entry['sha256'], filename
        font = TTFont(path)
        assert font['name'].getDebugName(1) == entry['family'], filename
        assert font['OS/2'].usWeightClass == entry['weight'], filename
        assert 'fvar' not in font, filename
        assert 'Open Font License' in font['name'].getDebugName(13), filename
        metadata = '\n'.join(n.toUnicode() for n in font['name'].names)
        assert not any(name in metadata for name in ('Microsoft YaHei', 'DengXian', '微软雅黑', '等线')), filename
        characters = set(GAIN_TEXT) if filename == 'gain_label.ttf' else app_characters() if filename == 'chinese.ttf' else set('0123456789RPMkm/h')
        required = {ord(c) for c in characters if c.isprintable()}
        missing = required - font.getBestCmap().keys()
        assert not missing, (filename, sorted(missing))
        print(f'{filename}: OFL metadata, hash, identity, {len(required)} required glyphs OK')
    for filename in ('NotoSansSC-OFL.txt', 'BarlowCondensed-OFL.txt'):
        assert (ASSETS / 'licenses' / filename).read_bytes() == sources[filename], filename
    print('All font notices match the verified upstream originals.')


if __name__ == '__main__':
    main()
