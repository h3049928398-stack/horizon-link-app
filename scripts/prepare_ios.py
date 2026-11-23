"""Local iPhone preparation. No upload, account login, or certificate handling."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_KEYS = {
    'DEVELOPER_NAME', 'CONTACT_EMAIL', 'PRIVACY_POLICY_URL',
    'PRIVACY_EFFECTIVE_DATE', 'APP_FILING_NUMBER',
}


def require_liquid_glass_sdk():
    version = subprocess.check_output(
        ['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True,
    ).strip()
    major = version.split('.')[0]
    if not major.isdecimal() or int(major) < 26:
        raise ValueError(f'iPhoneOS SDK 26 or newer is required for Liquid Glass (found {version!r}).')


def build_defines(root, metadata=None):
    url = json.loads((root / 'config/weekly-content.json').read_text(encoding='utf-8-sig'))['url']
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or
            parsed.password or parsed.query or parsed.fragment or any(c.isspace() for c in url)):
        raise ValueError('Weekly URL must be a stable public HTTPS URL without credentials/query/fragment')
    defines = {'WEEKLY_CONTENT_URL': url}
    if metadata:
        public = json.loads(Path(metadata).read_text(encoding='utf-8-sig'))
        if not isinstance(public, dict) or set(public) - PUBLIC_KEYS:
            raise ValueError('Only public release metadata keys are allowed')
        if any(not isinstance(v, str) for v in public.values()):
            raise ValueError('Public metadata values must be strings')
        defines.update(public)
    return defines


def source_files(root):
    app = root / 'flutter_app'
    for name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata'):
        yield app / name
    for folder in ('lib', 'assets', 'test'):
        yield from (p for p in (app / folder).rglob('*') if p.is_file())
    # Explicit iOS source allowlist: never transfer Pods, generated paths,
    # developer settings, provisioning profiles, or signing keys.
    ios = app / 'ios'
    for folder in ('Runner', 'RunnerTests'):
        for p in (ios / folder).rglob('*'):
            if (p.is_file() and not p.name.startswith('GeneratedPluginRegistrant') and
                    p.suffix in {'.swift', '.h', '.plist', '.storyboard', '.json', '.png', '.md'}):
                yield p
    for name in (
        'Flutter/Debug.xcconfig', 'Flutter/Release.xcconfig', 'Flutter/AppFrameworkInfo.plist',
        'Runner.xcodeproj/project.pbxproj',
        'Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
        'Runner.xcworkspace/contents.xcworkspacedata',
    ):
        yield ios / name
    for name in ('.gitignore', '.gitattributes', 'flutter_app/ios/.gitignore',
                 '.github/workflows/ios-self-test.yml',
                 'scripts/prepare_ios.py', 'docs/IOS_TESTING.md', 'config/weekly-content.json'):
        yield root / name


def export_source(root, output):
    # Source comes from this working tree, including current uncommitted work.
    # Deliberately avoid git archive (which would omit that work).
    files = sorted(set(source_files(root)))
    entries = []
    for p in files:
        if p.is_symlink() or not p.is_file() or not p.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'Missing or unsafe source path: {p}')
        data = p.read_bytes()
        entries.append((p.relative_to(root).as_posix(), data))
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        manifest = {}
        for name, data in entries:
            archive.writestr('Horizon-Link-iOS-source/' + name, data)
            manifest[name] = hashlib.sha256(data).hexdigest()
        archive.writestr('Horizon-Link-iOS-source/source-manifest.json',
                         json.dumps(manifest, ensure_ascii=False, indent=2))
    return len(entries)


def package_unsigned_ipa(app, output):
    """Package only a freshly built device app; signing happens later on Windows."""
    import plistlib
    with (app / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Expected a physical iPhoneOS build, not a simulator app')
    if not (app / info['CFBundleExecutable']).is_file():
        raise ValueError('Compiled app executable is missing')
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    # macOS ditto preserves framework symlinks and executable permissions.
    with tempfile.TemporaryDirectory(prefix='horizon-ipa-') as directory:
        payload = Path(directory) / 'Payload'
        payload.mkdir()
        subprocess.run(['/usr/bin/ditto', str(app), str(payload / 'Runner.app')], check=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(payload), str(output)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['export', 'prepare', 'run', 'build', 'unsigned-ipa'])
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], default='profile')
    parser.add_argument('--device', help='Physical device ID from flutter devices; required for run')
    parser.add_argument('--public-metadata', type=Path, help='Optional JSON with public fields only')
    parser.add_argument('--output', type=Path, help='New archive path (export or unsigned-ipa only)')
    args = parser.parse_args()
    if args.action == 'export':
        output = args.output or ROOT / 'artifacts' / (
            'Horizon-Link-iOS-source-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.zip')
        print(f'Exported {export_source(ROOT, output)} source files: {output.resolve()}')
        print('This is source, not an IPA. Build/sign on a Mac with Xcode.')
        return
    if sys.platform != 'darwin':
        parser.error('iOS prepare/run/build requires macOS + Xcode. Use export on Windows.')
    if args.action == 'run' and not args.device:
        parser.error('run requires --device from flutter devices; no implicit device selection')
    flutter = shutil.which('flutter')
    if not flutter or not shutil.which('xcodebuild'):
        parser.error('Install Flutter and full Xcode first; this script does not install tools')
    try:
        require_liquid_glass_sdk()
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        parser.error(f'{error} Select a full Xcode with the iPhoneOS SDK installed.')
    app = ROOT / 'flutter_app'
    defines = build_defines(ROOT, args.public_metadata)
    destination = ROOT / 'artifacts/ios'
    destination.mkdir(parents=True, exist_ok=True)
    config = destination / 'public-build-defines.json'
    config.write_text(json.dumps(defines, ensure_ascii=False, indent=2), encoding='utf-8')
    def run(arguments):
        subprocess.run([flutter, *arguments], cwd=app, check=True)
    # Resolve on the Mac; never copy Windows .dart_tool or Generated.xcconfig.
    run(['pub', 'get', '--enforce-lockfile'])
    common = [f'--{args.mode}', '--no-pub', f'--dart-define-from-file={config}']
    if args.action == 'prepare':
        run(['build', 'ios', '--config-only', '--no-codesign', *common])
        print('Prepared config only. Open flutter_app/ios/Runner.xcworkspace in Xcode.')
        print('Select Runner > Signing & Capabilities > Automatically manage signing > Personal Team.')
        print('Use a unique Bundle Identifier, then select the connected iPhone and Run.')
    elif args.action == 'run':
        run(['run', '-d', args.device, *common])
    elif args.action == 'unsigned-ipa':
        if args.mode == 'debug':
            parser.error('Use profile or release for an IPA launched without a debugger')
        run(['build', 'ios', '--no-codesign', *common])
        output = (args.output or destination / (
            'Horizon-Link-unsigned-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.ipa')).resolve()
        package_unsigned_ipa(app / 'build/ios/iphoneos/Runner.app', output)
        print(f'Unsigned IPA: {output}; must be signed before installation. No Apple credentials used.')
    else:
        run(['build', 'ios', *common])
        print('Built a signed device .app using your Xcode signing configuration; no IPA export/upload.')


if __name__ == '__main__':
    main()
