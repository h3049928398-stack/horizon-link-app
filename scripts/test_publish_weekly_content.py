"""Regression checks for the local weekly publishing workflow."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from publish_weekly_content import ROOT, validate


class PublishWeeklyTests(unittest.TestCase):
    def fixture(self):
        place = json.loads((ROOT / 'flutter_app/assets/map/places.json').read_text(encoding='utf-8'))[0]
        return {'schemaVersion': 1, 'revision': 1, 'periods': [{
            'id': 'test-week', 'name': {'zh': '仅供测试'},
            'startsAt': '2026-11-01T00:00:00+08:00', 'endsAt': '2026-11-08T00:00:00+08:00',
            'events': [{'id': 'test-event', 'type': 'seasonal', 'name': {'zh': '测试赛事'},
                        'locations': [{'id': 'test-location', 'name': {'zh': '测试位置'},
                                       'placeId': place['id'], 'source': 'Test fixture', 'quality': 'community'}]}]}]}

    def test_template_and_real_reference(self):
        validate(json.loads((ROOT / 'docs/weekly-content.template.json').read_text(encoding='utf-8')))
        validate(self.fixture())

    def test_reject_invalid_reference_duplicate_and_calendar(self):
        for change in ['reference', 'duplicate', 'calendar', 'coordinate']:
            data = self.fixture()
            location = data['periods'][0]['events'][0]['locations'][0]
            if change == 'reference':
                location['placeId'] = 'nonexistent-place'
            elif change == 'duplicate':
                location['id'] = 'test-week'
            elif change == 'calendar':
                data['periods'][0]['startsAt'] = '2026-02-30T00:00:00Z'
            else:
                del location['placeId']
                location['coordinates'] = {'x': 1e20, 'y': 0, 'z': 0}
            with self.assertRaises(ValueError):
                validate(data)

    def test_prepare_review_revision_guard_and_restore(self):
        with tempfile.TemporaryDirectory(prefix='weekly-publish-test-', dir=ROOT / '.tools') as directory:
            folder = Path(directory).resolve()
            self.assertTrue(folder.is_relative_to((ROOT / '.tools').resolve()))
            source, output, review = [folder / n for n in ('source.json', 'weekly.json', 'review.md')]
            source.write_text(json.dumps(self.fixture(), ensure_ascii=False), encoding='utf-8')
            command = [sys.executable, str(ROOT / 'scripts/publish_weekly_content.py'),
                       '--input', str(source), '--output', str(output), '--preview', str(review)]
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('仅供测试', review.read_text(encoding='utf-8'))
            first = output.read_bytes()
            result = subprocess.run(command, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), first)
            changed = copy.deepcopy(self.fixture())
            changed['periods'][0]['name']['zh'] = '修正后的测试内容'
            source.write_text(json.dumps(changed, ensure_ascii=False), encoding='utf-8')
            result = subprocess.run(command + ['--revision', '2'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            source.write_bytes(first)
            result = subprocess.run(command + ['--revision', '3'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            restored = json.loads(output.read_text(encoding='utf-8'))
            self.assertEqual(restored['revision'], 3)
            self.assertEqual(restored['periods'], self.fixture()['periods'])


if __name__ == '__main__':
    unittest.main()
