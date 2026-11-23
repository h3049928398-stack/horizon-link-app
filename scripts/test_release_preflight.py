import unittest
from release_preflight import validate


class ReleasePreflightTest(unittest.TestCase):
    def setUp(self):
        # Explicit test fixtures, never real filing information or release input.
        self.metadata = dict(DEVELOPER_NAME='Test fixture', CONTACT_EMAIL='test@invalid.test',
                             PRIVACY_POLICY_URL='https://invalid.test/privacy',
                             PRIVACY_EFFECTIVE_DATE='2026-11-02', APP_FILING_NUMBER='TEST-ONLY')
        self.weekly = {'url': 'https://invalid.test/weekly.json'}

    def test_valid_public_fields(self):
        result = validate(self.metadata, self.weekly)
        self.assertEqual(result['WEEKLY_CONTENT_URL'], self.weekly['url'])
        self.assertNotIn('HL_STORE_PASSWORD', result)

    def test_missing_identity_blocks(self):
        self.metadata['DEVELOPER_NAME'] = ''
        with self.assertRaises(ValueError): validate(self.metadata, self.weekly)

    def test_missing_filing_blocks(self):
        self.metadata['APP_FILING_NUMBER'] = ''
        with self.assertRaises(ValueError): validate(self.metadata, self.weekly)

    def test_missing_weekly_blocks(self):
        with self.assertRaises(ValueError): validate(self.metadata, {})

    def test_unstable_or_unsafe_urls_block(self):
        for url in ['http://invalid.test/x', 'https://u:p@invalid.test/x', 'https://invalid.test/x?sign=secret', 'https://invalid.test/x#y']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate(self.metadata, {'url': url})

    def test_invalid_date_and_placeholder_block(self):
        self.metadata['PRIVACY_EFFECTIVE_DATE'] = '2026-99-00'
        with self.assertRaises(ValueError): validate(self.metadata, self.weekly)
        self.metadata['PRIVACY_EFFECTIVE_DATE'] = '2026-11-02'
        self.metadata['DEVELOPER_NAME'] = '待补充'
        with self.assertRaises(ValueError): validate(self.metadata, self.weekly)


if __name__ == '__main__':
    unittest.main()
