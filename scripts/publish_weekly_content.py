"""Validate and prepare a weekly COS JSON object; never uploads or handles credentials."""
import argparse
from datetime import datetime
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 1024 * 1024


def validate(data):
    places = {p['id'] for p in json.loads(
        (ROOT / 'flutter_app/assets/map/places.json').read_text(encoding='utf-8'))}
    seen = set()

    def obj(value):
        if not isinstance(value, dict):
            raise ValueError('Expected object')
        return value

    def text(value):
        if not isinstance(value, str) or not value.strip() or len(value) > 1000:
            raise ValueError('Expected nonempty text (max 1000 characters)')
        return value.strip()

    def ident(value):
        value = text(value)
        if not re.fullmatch(r'[a-zA-Z0-9_.-]{1,100}', value) or value in seen:
            raise ValueError('Invalid or duplicate ID: ' + value)
        seen.add(value)

    def name(value):
        value = obj(value)
        text(value.get('zh'))
        if value.get('en') is not None:
            text(value['en'])

    def items(value):
        if not isinstance(value, list) or len(value) > 1000:
            raise ValueError('Expected list of at most 1000 items')
        return value

    def date(value):
        value = text(value)
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})', value):
            raise ValueError('Use an ISO timestamp with explicit timezone')
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if abs(result.utcoffset().total_seconds()) > 14 * 3600:
            raise ValueError('Invalid timezone offset')
        return result

    obj(data)
    if type(data.get('schemaVersion')) is not int or data['schemaVersion'] != 1:
        raise ValueError('schemaVersion must be 1')
    if type(data.get('revision')) is not int or not 1 <= data['revision'] <= 2147483647:
        raise ValueError('revision must be a positive 32-bit integer')
    periods = []
    for p in items(data.get('periods')):
        obj(p); ident(p.get('id')); name(p.get('name'))
        start, end = date(p.get('startsAt')), date(p.get('endsAt'))
        if start >= end:
            raise ValueError('Period must end after start')
        periods.append((start, end))
        for e in items(p.get('events')):
            obj(e); ident(e.get('id')); name(e.get('name'))
            if e.get('type') not in ('seasonal', 'treasure', 'other'):
                raise ValueError('Unknown event type')
            for loc in items(e.get('locations')):
                obj(loc); ident(loc.get('id')); name(loc.get('name')); text(loc.get('source'))
                place_id, coordinate = loc.get('placeId'), loc.get('coordinates')
                if place_id is not None:
                    if text(place_id) not in places:
                        raise ValueError('Unknown placeId: ' + str(place_id))
                    if coordinate is not None:
                        raise ValueError('Choose placeId OR coordinates')
                if coordinate is not None:
                    obj(coordinate)
                    xyz = [coordinate.get(k) for k in ('x', 'y', 'z')]
                    if any(type(v) not in (int, float) or not math.isfinite(v) for v in xyz):
                        raise ValueError('Coordinates must be finite numbers')
                    x, y, z = xyz
                    if not (0 <= 582.896 + x * .046504 <= 1024 and
                            0 <= 499.376 - z * .046504 <= 1024 and abs(y) <= 10000):
                        raise ValueError('Coordinates outside map')
                located = place_id is not None or coordinate is not None
                if loc.get('quality') not in (('community', 'verified') if located else ('unknown',)):
                    raise ValueError('Invalid location quality')
    periods.sort()
    if any(b[0] < a[1] for a, b in zip(periods, periods[1:])):
        raise ValueError('Periods must not overlap')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', type=Path, help='Prepared weekly.json; omitted for validation only')
    parser.add_argument('--revision', type=int, help='Set a new revision, including when restoring old content')
    parser.add_argument('--previous', type=Path, help='Latest published JSON, used to enforce revision increase')
    parser.add_argument('--preview', type=Path, help='Write a readable local review (do not upload)')
    args = parser.parse_args()
    if args.input.stat().st_size > MAX_BYTES:
        parser.error('Input exceeds 1 MiB')
    data = json.loads(args.input.read_text(encoding='utf-8-sig'))
    if args.revision is not None:
        data['revision'] = args.revision
    validate(data)
    previous_path = args.previous or (args.output if args.output and args.output.exists() else None)
    if previous_path:
        previous = json.loads(previous_path.read_text(encoding='utf-8-sig'))
        if data['revision'] <= previous['revision']:
            parser.error('Revision must exceed the latest published revision')
    encoded = (json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode('utf-8')
    if len(encoded) > MAX_BYTES:
        parser.error('Output exceeds 1 MiB')
    if args.output:
        if args.output.resolve() == args.input.resolve():
            parser.error('Keep source and prepared output separate')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_suffix(args.output.suffix + '.tmp')
        temporary.write_bytes(encoded)
        temporary.replace(args.output)
    if args.preview:
        lines = [f"# Weekly content r{data['revision']}", '', 'Review only; locations still require game verification.']
        for p in data['periods']:
            lines += ['', p['name']['zh'], f"{p['startsAt']} — {p['endsAt']}"]
            for e in p['events']:
                lines += [f"- [{e['type']}] {e['name']['zh']}"]
                for loc in e['locations']:
                    target = loc.get('placeId') or loc.get('coordinates') or 'LOCATION PENDING'
                    lines += [f"  - {loc['name']['zh']}: {target}; {loc['quality']}; {loc['source']}"]
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        args.preview.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f"Validated revision {data['revision']}: {len(data['periods'])} periods, {len(encoded)} bytes. No upload performed.")


if __name__ == '__main__':
    main()
