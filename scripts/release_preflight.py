"""Validate public metadata, emit Dart defines. Never reads signing passwords."""
import argparse
import datetime
import json
import pathlib
import re
from urllib.parse import urlparse

FIELDS = ('DEVELOPER_NAME', 'CONTACT_EMAIL', 'PRIVACY_POLICY_URL',
          'PRIVACY_EFFECTIVE_DATE', 'APP_FILING_NUMBER')


def validate(metadata, weekly):
    for key in FIELDS:
        value = metadata.get(key)
        if not isinstance(value, str) or not value.strip() or any(
                marker in value.lower() for marker in ('待补', 'todo', 'example', '<', '>')):
            raise ValueError(f'Missing or placeholder public metadata: {key}')
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', metadata['CONTACT_EMAIL']):
        raise ValueError('Invalid CONTACT_EMAIL')
    datetime.date.fromisoformat(metadata['PRIVACY_EFFECTIVE_DATE'])
    values = {key: metadata[key].strip() for key in FIELDS}
    values['WEEKLY_CONTENT_URL'] = weekly.get('url', '')
    for key in ('WEEKLY_CONTENT_URL', 'PRIVACY_POLICY_URL'):
        uri = urlparse(values[key])
        if uri.scheme != 'https' or not uri.hostname or uri.username or uri.password or uri.fragment or uri.query:
            raise ValueError(f'{key} must be a stable public HTTPS URL without credentials, query or fragment')
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', required=True)
    parser.add_argument('--weekly', required=True)
    parser.add_argument('--output')
    args = parser.parse_args()
    try:
        data = validate(json.loads(pathlib.Path(args.metadata).read_text(encoding='utf-8-sig')),
                        json.loads(pathlib.Path(args.weekly).read_text(encoding='utf-8-sig')))
    except (ValueError, OSError) as exc:
        parser.exit(1, f'Release blocked: {exc}\n')
    if args.output:
        target = pathlib.Path(args.output)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Public metadata passed syntax checks; identity, filing and URL availability still require review.')


if __name__ == '__main__':
    main()
