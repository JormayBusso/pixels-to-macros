import json
import pathlib
from urllib.parse import urlparse

recipes = json.loads(pathlib.Path('assets/bundled_recipes.json').read_text())
have_urls = set()
for r in recipes:
    u = (r.get('source_url') or '').strip()
    if u:
        have_urls.add(u)
        have_urls.add(u.rstrip('/'))

rows = []
for line in pathlib.Path('recipe_urls.txt').read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split(None, 1)
    if len(parts) == 2:
        lang, url = parts
    else:
        lang, url = '?', parts[0]
    rows.append((lang, url))

by_host = {}
for lang, url in rows:
    host = urlparse(url).netloc.lower()
    by_host.setdefault(host, {'total': 0, 'unscraped': 0})
    by_host[host]['total'] += 1
    if url not in have_urls and url.rstrip('/') not in have_urls:
        by_host[host]['unscraped'] += 1

for host, d in sorted(by_host.items(), key=lambda x: -x[1]['unscraped']):
    print(f"{host}: total={d['total']} unscraped={d['unscraped']}")
