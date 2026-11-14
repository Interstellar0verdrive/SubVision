"""Checks the EN/IT catalogs of the app (macos/Native/SubVision/Resources/locales/{en,it}/app.json):
same keys, same placeholders in each pair, both plural forms (.uno/.altri), only {name}
placeholders (no Python formats), {{ }} for literal braces, keys sorted, keys in the known areas.
Run from anywhere:  python3 -I tools/check_locales.py   (exit code 1 on any problem)."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / 'macos/Native/SubVision/Resources/locales'
AREAS = {'sidebar', 'process', 'review', 'inspector', 'preview', 'fix', 'report', 'settings', 'tools', 'alerts',
         'menu', 'notify', 'errors', 'steps', 'common'}
PLACEHOLDER = re.compile(r'(?<!\{)\{([^{}]*)\}(?!\})')


def placeholders(text):
    # drop literal {{ and }} first, then collect {name}
    return sorted(PLACEHOLDER.findall(text.replace('{{', '').replace('}}', '')))


def load(lang):
    path = LOC / lang / 'app.json'
    raw = path.read_text(encoding='utf-8')
    data = json.loads(raw)
    return path, raw, data


problems = []
(pen, raw_en, en), (pit, raw_it, it) = load('en'), load('it')
for lang, path, raw, d in (('en', pen, raw_en, en), ('it', pit, raw_it, it)):
    if list(d) != sorted(d):
        problems.append(f'{lang}: keys not sorted')
    for k, v in d.items():
        parts = k.split('.')
        if parts[0] != 'app' or len(parts) < 3 or parts[1] not in AREAS:
            problems.append(f'{lang}: {k}: not app.<area>.<name> with a known area')
        for p in placeholders(v):
            if not re.fullmatch(r'[a-z_][a-z0-9_]*', p):
                problems.append(f'{lang}: {k}: placeholder {{{p}}} is not {{name}}')
        if not v.strip():
            problems.append(f'{lang}: {k}: empty text')
only_en, only_it = sorted(set(en) - set(it)), sorted(set(it) - set(en))
for k in only_en:
    problems.append(f'only in en: {k}')
for k in only_it:
    problems.append(f'only in it: {k}')
for k in sorted(set(en) & set(it)):
    if placeholders(en[k]) != placeholders(it[k]):
        problems.append(f'{k}: placeholders differ: en {placeholders(en[k])} / it {placeholders(it[k])}')
for k in en:
    if k.endswith('.uno') and k[:-4] + '.altri' not in en:
        problems.append(f'{k}: .altri missing')
    if k.endswith('.altri') and k[:-6] + '.uno' not in en:
        problems.append(f'{k}: .uno missing')

areas = {}
for k in en:
    areas[k.split('.')[1]] = areas.get(k.split('.')[1], 0) + 1
plural = sum(1 for k in en if k.endswith('.uno'))
print(f'en: {len(en)} keys · it: {len(it)} keys · {plural} plurals (.uno/.altri)')
print('areas: ' + ', '.join(f'{a} {n}' for a, n in sorted(areas.items())))
if problems:
    print(f'{len(problems)} problems:')
    for p in problems:
        print('  ' + p)
    sys.exit(1)
print('OK: same keys, same placeholders, plural pairs complete, keys sorted.')
