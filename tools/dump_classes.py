#!/usr/bin/env python3
"""从 Mach-O 字符串表恢复 Swift/ObjC 类型清单，按模块分组。用法: dump_classes.py <strings.txt> <outdir>"""
import re, sys, json, os, collections

def main(src, outdir):
    txt = open(src, encoding='utf-8', errors='replace').read()
    types = collections.defaultdict(set)
    # _TtC<len><Module><len><Type>  嵌套: _TtCV / _TtCC
    for m in re.finditer(r'_Tt[CV](\d+)([A-Za-z][A-Za-z0-9_]*?)\d+', txt):
        ml = int(m.group(1)); mod = m.group(2)[:ml]
        types[mod].add(m.group(0))
    # swift mangled _$s / $s with module length
    for m in re.finditer(r'\$s(\d+)([A-Za-z][A-Za-z0-9_]*)', txt):
        ml = int(m.group(1)); mod = m.group(2)[:ml]
        if len(mod) == ml and mod[0].isupper():
            types[mod]
    os.makedirs(outdir, exist_ok=True)
    total = 0
    rows = []
    for mod, names in sorted(types.items(), key=lambda kv: -len(kv[1])):
        total += len(names)
        rows.append((mod, len(names)))
        with open(os.path.join(outdir, f'{mod}.txt'), 'w') as f:
            f.write('\n'.join(sorted(names)))
    print(f'modules={len(types)} types={total}')
    for mod, n in rows[:40]:
        print(f'{n:6d}  {mod}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
