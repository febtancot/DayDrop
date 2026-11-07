#!/usr/bin/env python3
"""Build a bounded asset/version allowlist without modifying the signed feed."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
site = root / 'Product_Site'
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
assets = {}
versions = set()
for item in ET.parse(site / 'updates/appcast.xml').findall('./channel/item'):
    version = item.findtext('sparkle:shortVersionString', namespaces=ns)
    if not version:
        raise ValueError('Missing release version')
    versions.add(version)
    for enclosure in item.findall('.//enclosure'):
        from urllib.parse import urlparse
        path = urlparse(enclosure.attrib['url']).path
        if not path.startswith('/downloads/') or not (site / path.lstrip('/')).is_file():
            raise ValueError(f'Missing release asset: {path}')
        assets[path] = {'version': version, 'packageType': 'delta' if path.endswith('.delta') else 'full'}
# Include retained full installers even after Sparkle drops them from its feed.
import re
for dmg in (site / 'downloads').glob('DayDrop-*.dmg'):
    match = re.fullmatch(r'DayDrop-(\d+\.\d+\.\d+)\.dmg', dmg.name)
    if match:
        versions.add(match[1])
        assets['/downloads/' + dmg.name] = {'version': match[1], 'packageType': 'full'}
catalog = {'versions': sorted(versions), 'assets': assets}
(site / 'release-catalog.js').write_text('export default ' + json.dumps(catalog, indent=2) + ';\n')
print(f'Statistics catalog: {len(assets)} release assets, {len(versions)} versions')
