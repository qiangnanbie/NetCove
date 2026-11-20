#!/usr/bin/env python3
"""把原 App 的本地化 plist 转成 NetCove 词条（品牌词替换 + 键名加前缀）。
用法: rebrand.py <原 .app 目录> <输出目录>
注意：产出仅作参考对齐，正式文案建议自行撰写以免侵权。"""
import plistlib, sys, os, glob

REPL = [('Rex', 'NetCove'), ('rexnow', 'netcove'), ('Dino', 'Cove'), ('drivemby', 'partner')]

def convert(app_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for lproj in sorted(glob.glob(os.path.join(app_dir, '*.lproj'))):
        lang = os.path.basename(lproj).replace('.lproj', '')
        merged = {}
        for f in sorted(glob.glob(os.path.join(lproj, '*.strings'))):
            try:
                data = plistlib.load(open(f, 'rb'))
            except Exception:
                continue
            ns = os.path.basename(f).replace('.strings', '').lower()
            for k, v in data.items():
                if not isinstance(v, str):
                    continue
                for a, b in REPL:
                    v = v.replace(a, b)
                merged[f'{ns}.{k}'] = v
        if not merged:
            continue
        dst = os.path.join(out_dir, f'{lang}.lproj')
        os.makedirs(dst, exist_ok=True)
        with open(os.path.join(dst, 'Localizable.strings'), 'w') as fh:
            for k, v in merged.items():
                fh.write(f'"{k}" = "{v}";\n')
        print(f'{lang}: {len(merged)} keys')

if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2])
