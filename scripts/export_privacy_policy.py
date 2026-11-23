"""Export the same bilingual policy displayed by the App as static HTML (no upload)."""
import argparse
import html
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', default='.tools/release/public-metadata.json')
    parser.add_argument('--output', default='artifacts/release-prep/privacy.html')
    args = parser.parse_args()
    metadata = json.loads(pathlib.Path(args.metadata).read_text(encoding='utf-8-sig'))
    source = (ROOT / 'flutter_app/lib/pages/privacy_page.dart').read_text(encoding='utf-8')
    texts = re.findall(r"return '''(.*?)''';", source, re.S)
    if len(texts) != 2:
        raise ValueError('Policy source changed; update exporter before publishing')
    release = (ROOT / 'flutter_app/lib/services/release_info.dart').read_text(encoding='utf-8')
    version = re.search(r"policyVersion = '([^']+)'", release).group(1)
    fields = {'effectiveDate': 'PRIVACY_EFFECTIVE_DATE', 'developer': 'DEVELOPER_NAME', 'email': 'CONTACT_EMAIL'}
    sections = []
    for language, text in zip(('en', 'zh-CN'), texts):
        text = text.replace('${ReleaseInfo.policyVersion}', version)
        for field, key in fields.items():
            text = text.replace('${info(ReleaseInfo.' + field + ')}', metadata.get(key) or ('[Pending before release]' if language == 'en' else '【发布前待补充】'))
        if '${' in text:
            raise ValueError('Unresolved policy placeholder')
        sections.append(f'<section lang="{language}" id="{language}"><pre>{html.escape(text)}</pre></section>')
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Horizon Link 隐私政策 / Privacy</title>
<style>body{max-width:760px;margin:auto;padding:24px;font:16px/1.85 system-ui,sans-serif;color:#17232b;background:#f6f8fa}nav{display:flex;gap:24px}section{margin:32px 0;padding:24px;background:white;border-radius:16px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:inherit}</style>
<nav><a href="#zh-CN">中文</a><a href="#en">English</a></nav>
''' + ''.join(reversed(sections)) + '</html>\n', encoding='utf-8')
    print(f'Generated {output}; no upload performed. Complete pending identity/date before publishing.')


if __name__ == '__main__':
    main()
