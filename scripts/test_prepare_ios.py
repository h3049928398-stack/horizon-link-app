import json
import plistlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from prepare_ios import build_defines, export_source, package_unsigned_ipa, source_files
from prepare_ios import require_liquid_glass_sdk


class IosPreparationTest(unittest.TestCase):
    def test_liquid_glass_requires_ios_26_sdk_or_newer(self):
        with patch('prepare_ios.subprocess.check_output') as run:
            for version in ('26.0\n', '27.2\n'):
                run.return_value = version
                require_liquid_glass_sdk()
            for version in ('18.5\n', ''):
                run.return_value = version
                with self.assertRaisesRegex(ValueError, 'SDK 26'):
                    require_liquid_glass_sdk()

    def test_weekly_url_is_kept_and_secrets_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'config').mkdir()
            source = root / 'config/weekly-content.json'
            source.write_text(json.dumps({'url': 'https://example.com/weekly.json'}))
            self.assertEqual(build_defines(root), {'WEEKLY_CONTENT_URL': 'https://example.com/weekly.json'})
            metadata = root / 'private.json'
            metadata.write_text(json.dumps({'APPLE_PASSWORD': 'fixture-only'}))
            with self.assertRaises(ValueError):
                build_defines(root, metadata)
            for url in ('http://example.com/x', 'https://u:p@example.com/x',
                        'https://example.com/x?token=x', 'https://example.com/x#fragment'):
                source.write_text(json.dumps({'url': url}))
                with self.subTest(url=url), self.assertRaises(ValueError):
                    build_defines(root)

    def test_archive_uses_current_bytes_manifest_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'app.dart'
            source.write_bytes(b'current uncommitted work')
            output = root / 'source.zip'
            with patch('prepare_ios.source_files', return_value=[source]):
                self.assertEqual(export_source(root, output), 1)
                with self.assertRaises(FileExistsError):
                    export_source(root, output)
            with zipfile.ZipFile(output) as archive:
                prefix = 'Horizon-Link-iOS-source/'
                self.assertEqual(archive.read(prefix + 'app.dart'), source.read_bytes())
                self.assertEqual(len(json.loads(archive.read(prefix + 'source-manifest.json'))), 1)

    def test_archive_rejects_file_outside_root(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            root = parent / 'root'
            root.mkdir()
            outside = parent / 'secret'
            outside.write_text('fixture')
            with patch('prepare_ios.source_files', return_value=[outside]):
                with self.assertRaises(ValueError):
                    export_source(root, root / 'source.zip')

    def test_allowlist_omits_credentials_and_generated_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ('lib', 'assets', 'test', 'ios/Runner', 'ios/RunnerTests'):
                (root / 'flutter_app' / folder).mkdir(parents=True, exist_ok=True)
            for p in source_files(root):
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('fixture')
            excluded = [
                '.tools/private.json', 'config/other-private.json',
                'flutter_app/.dart_tool/package_config.json',
                'flutter_app/ios/Flutter/Generated.xcconfig',
                'flutter_app/ios/Runner/GeneratedPluginRegistrant.m',
                'flutter_app/ios/Runner/signing.p12',
                'flutter_app/ios/Runner/account.mobileprovision',
                'flutter_app/ios/Runner.xcodeproj/xcuserdata/user.xcuserstate',
            ]
            for name in excluded:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('private fixture')
            selected = {p.relative_to(root).as_posix() for p in source_files(root)}
            self.assertTrue(selected.isdisjoint(excluded))

    def test_ipa_packaging_rejects_simulator_and_missing_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'Runner.app'
            app.mkdir()
            for platform in ('iPhoneSimulator', 'iPhoneOS'):
                (app / 'Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleSupportedPlatforms': [platform], 'CFBundleExecutable': 'Runner',
                }))
                with self.subTest(platform=platform), self.assertRaises(ValueError):
                    package_unsigned_ipa(app, root / 'unsigned.ipa')


if __name__ == '__main__':
    unittest.main()
