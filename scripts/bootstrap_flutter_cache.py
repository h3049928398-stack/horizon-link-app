"""Import the SDK's bundled package archives without downloading dependencies."""
import hashlib
import sys
import tarfile
from pathlib import Path

sdk = Path(sys.argv[1]).resolve()
cache = Path(sys.argv[2]).resolve()
packages = cache / 'hosted' / 'pub.dev'
hashes = cache / 'hosted-hashes' / 'pub.dev'
packages.mkdir(parents=True, exist_ok=True)
hashes.mkdir(parents=True, exist_ok=True)
count = 0
for archive in sorted((sdk / '.pub-preload-cache').glob('*.tar.gz')):
    slug = archive.name[:-7]
    destination = (packages / slug).resolve()
    if not destination.is_relative_to(packages.resolve()):
        raise ValueError('Archive name escapes cache')
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:gz') as bundle:
        for entry in bundle:
            target = (destination / entry.name).resolve()
            if not target.is_relative_to(destination):
                raise ValueError('Archive entry escapes package')
            if entry.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif entry.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                stream = bundle.extractfile(entry)
                if stream:
                    target.write_bytes(stream.read())
    (hashes / (slug + '.sha256')).write_text(hashlib.sha256(archive.read_bytes()).hexdigest(), encoding='utf-8')
    count += 1
print(f'Imported {count} bundled packages into {cache} (offline).')
