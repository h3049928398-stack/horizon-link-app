"""Prepare Nginx and App endpoint configuration; never deploy or overwrite live config."""
import argparse
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


def prepare(endpoint, ca_bundle):
    if any(ord(c) <= 32 or ord(c) == 127 for c in endpoint):
        raise ValueError('Endpoint must not contain whitespace or control characters.')
    uri = urlsplit(endpoint)
    # Restrict inputs to literals safe for Nginx configuration, not directives.
    if (uri.scheme != 'https' or not uri.hostname or uri.username is not None
            or uri.password is not None or uri.query or uri.fragment
            or not re.fullmatch(r'[a-zA-Z0-9.-]+(?::443)?', uri.netloc)
            or not re.fullmatch(r'(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}', uri.hostname)
            or not re.fullmatch(r'/[a-zA-Z0-9_/-]*weekly\.json', uri.path)
            or any(p in ('.', '..') for p in uri.path.split('/'))
            or uri.hostname.endswith('.myqcloud.com')):
        raise ValueError('Use your stable HTTPS domain endpoint ending in /weekly.json; no credentials/query/fragment.')
    if not re.fullmatch(r'(?:/|[a-zA-Z]:/)[a-zA-Z0-9_./-]+', ca_bundle) or '..' in ca_bundle.split('/'):
        raise ValueError('CA bundle must be an absolute Linux or Windows path using forward slashes, without whitespace or directives.')
    template = (ROOT / 'deploy/weekly-gateway/location.conf.template').read_text(encoding='utf-8')
    nginx = template.replace('@@PATH@@', uri.path).replace('@@CA_BUNDLE@@', ca_bundle)
    return nginx, {'url': endpoint}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', required=True)
    parser.add_argument('--ca-bundle', default='/etc/ssl/certs/ca-certificates.crt')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'artifacts/weekly-gateway')
    args = parser.parse_args()
    try:
        nginx, app = prepare(args.endpoint, args.ca_bundle)
    except ValueError as error:
        parser.error(str(error))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / 'weekly-location.conf').write_text(nginx, encoding='utf-8')
    (args.output_dir / 'weekly-content.json').write_text(json.dumps(app, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {args.output_dir}. No deployment or active App configuration change performed.')


if __name__ == '__main__':
    main()
