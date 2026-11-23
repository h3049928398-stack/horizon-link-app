import unittest

from configure_weekly_gateway import prepare


class GatewayConfigurationTests(unittest.TestCase):
    def test_windows_ca_path(self):
        nginx, _ = prepare('https://content.test.org/weekly/weekly.json', 'C:/BtSoft/nginx/conf/cacert.pem')
        self.assertIn('proxy_ssl_trusted_certificate C:/BtSoft/nginx/conf/cacert.pem;', nginx)
        self.assertIn('expires off;', nginx)

    def test_fixed_origin_and_no_client_forwarding(self):
        nginx, app = prepare('https://content.test.org/weekly/weekly.json', '/etc/ssl/certs/ca-certificates.crt')
        self.assertEqual(app['url'], 'https://content.test.org/weekly/weekly.json')
        self.assertIn('location = /weekly/weekly.json', nginx)
        self.assertIn('set $args "";', nginx)
        self.assertIn('proxy_pass_request_headers off;', nginx)
        self.assertIn('proxy_ssl_verify on;', nginx)
        self.assertIn('proxy_cache off;', nginx)
        self.assertNotIn('@@', nginx)
        self.assertNotIn('$http_', nginx)
        self.assertNotIn('$remote_addr', nginx)
        self.assertNotIn('return 30', nginx)

    def test_invalid_endpoint_rejected(self):
        for endpoint in ('http://content.test.org/weekly.json',
                         'https://user:pass@content.test.org/weekly.json',
                         'https://content.test.org/weekly.json?url=https://evil.org',
                         'https://content.test.org/weekly.json#fragment',
                         'https://content.test.org:8443/weekly.json',
                         'https://content.test.org/a;return 200;/weekly.json',
                         'https://content.test.org/../weekly.json',
                         'https://content.test.org/weekly.json\n}',
                         'https://bucket.cos.ap-guangzhou.myqcloud.com/weekly.json'):
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError):
                prepare(endpoint, '/etc/ssl/certs/ca-certificates.crt')

    def test_unsafe_ca_path_rejected(self):
        for ca in ('relative.crt', '/tmp/a;ssl_verify off;', '/tmp/a\nb', '/tmp/../cert'):
            with self.subTest(ca=ca), self.assertRaises(ValueError):
                prepare('https://content.test.org/weekly.json', ca)


if __name__ == '__main__':
    unittest.main()
