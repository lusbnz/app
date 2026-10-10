#!/usr/bin/env python3
"""Giữ Xu/Localizable.xcstrings khớp với chuỗi trong mã nguồn.

`xcodebuild` không tự ghi khóa mới vào catalog, nên sau khi build, chạy:

    python3 scripts/sync_strings.py            # chỉ báo: khóa nào có trong mã mà catalog chưa có hoặc chưa có bản en
    python3 scripts/sync_strings.py --write    # thêm các khóa còn thiếu vào catalog (bản en để trống)
    python3 scripts/sync_strings.py --translate scripts/en.py   # nạp bản dịch: tệp Python có dict T {khóa: "en" hoặc ("one", "other")}

Đọc chuỗi từ các tệp `*.stringsdata` mà trình biên dịch đã sinh trong `build/DerivedData`.
"""
import glob
import json
import os
import runpy
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, 'Xu', 'Localizable.xcstrings')


def load():
    return json.load(open(PATH, encoding='utf-8'))


def save(catalog):
    open(PATH, 'w', encoding='utf-8').write(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(',', ' : ')) + '\n')


def keys_in_code():
    pattern = os.path.join(ROOT, 'build/DerivedData/Build/Intermediates.noindex/Xu.build/Debug-iphonesimulator/Xu.build/Objects-normal/*/*.stringsdata')
    found = set()
    for path in glob.glob(pattern):
        for item in json.load(open(path, encoding='utf-8')).get('tables', {}).get('Localizable', []):
            found.add(item['key'])
    return found


def translate(catalog, file):
    translations = runpy.run_path(file)['T']
    for key, text in translations.items():
        localizations = catalog['strings'].setdefault(key, {}).setdefault('localizations', {})
        if isinstance(text, tuple):
            localizations['en'] = {'variations': {'plural': {
                'one': {'stringUnit': {'state': 'translated', 'value': text[0]}},
                'other': {'stringUnit': {'state': 'translated', 'value': text[1]}}}}}
        else:
            localizations['en'] = {'stringUnit': {'state': 'translated', 'value': text}}
        if 'vi' in localizations and 'stringUnit' in localizations['vi']:
            localizations['vi']['stringUnit']['state'] = 'translated'
    print(f'đã nạp {len(translations)} bản dịch')


def main():
    catalog = load()
    strings = catalog['strings']
    if '--translate' in sys.argv:
        translate(catalog, sys.argv[sys.argv.index('--translate') + 1])
        save(catalog)
    found = keys_in_code()
    added = sorted(found - set(strings))
    if '--write' in sys.argv:
        for key in added:
            strings[key] = {}
        if added:
            save(catalog)
    missing = [k for k in sorted(found) if not (strings.get(k) and 'en' in (strings[k].get('localizations') or {}))]
    print(f'khóa trong mã: {len(found)} | chưa có trong catalog: {len(added)} | chưa có bản en: {len(missing)}')
    for key in missing:
        print(json.dumps(key, ensure_ascii=False))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
