#!/usr/bin/env python3
"""导出 ObjC/Swift 类名与选择子清单，按模块分组。
用法: dump_objc.py <MachO 路径> <输出目录>"""
import struct, sys, os, re, collections

def sections(d):
    ncmds = struct.unpack('<I', d[16:20])[0]; p = 32; out = {}
    for _ in range(ncmds):
        cmd, cs = struct.unpack('<II', d[p:p+8])
        if cmd == 0x19:
            sg = d[p+8:p+24].split(b'\0')[0].decode()
            ns = struct.unpack('<I', d[p+64:p+68])[0]; q = p + 72
            for _ in range(ns):
                sn = d[q:q+16].split(b'\0')[0].decode()
                addr, size, off = struct.unpack('<QQI', d[q+32:q+52])
                out[(sg, sn)] = (off, size); q += 80
        p += cs
    return out

def strings(d, sec):
    off, size = sec
    return [x.decode('utf-8', 'replace') for x in d[off:off+size].split(b'\0') if x]

def read_len(s, i):
    """读 Swift 的 <十进制长度><内容>"""
    j = i
    while j < len(s) and s[j].isdigit(): j += 1
    if j == i: return None, i
    n = int(s[i:j])
    return s[j:j+n], j + n

def parse_type(sym):
    """_TtC3Rex22CatalogServerPageCache -> ('Rex','CatalogServerPageCache')"""
    m = re.match(r'_Tt[CV]', sym)
    if not m: return None
    i = m.end()
    mod, i = read_len(sym, i)
    if not mod: return None
    # 私有判别串 P33_<32hex>
    if i < len(sym) and sym[i] == 'P':
        _, i = read_len(sym, i + 1)
    name, i = read_len(sym, i)
    return (mod, name) if name else None

def main(binpath, outdir):
    d = open(binpath, 'rb').read(); s = sections(d)
    classes = strings(d, s[('__TEXT', '__objc_classname')])
    meths = strings(d, s.get(('__TEXT', '__objc_methname'), (0, 0)))
    os.makedirs(outdir, exist_ok=True)
    mods = collections.defaultdict(set); other = set()
    for c in classes:
        r = parse_type(c)
        if r: mods[r[0]].add(r[1])
        elif not c.startswith('_Tt'): other.add(c)
    for mod, names in mods.items():
        open(os.path.join(outdir, f'{mod}.types.txt'), 'w').write('\n'.join(sorted(names)))
    open(os.path.join(outdir, '_objc_system_classes.txt'), 'w').write('\n'.join(sorted(other)))
    sels = sorted(set(x for x in meths if re.match(r'^[a-zA-Z_$]', x)))
    open(os.path.join(outdir, '_selectors.txt'), 'w').write('\n'.join(sels))
    total = sum(len(v) for v in mods.values())
    print(f'first-party Swift types={total} / modules={len(mods)}；ObjC+系统类={len(other)}；选择子={len(sels)}')
    for mod, names in sorted(mods.items(), key=lambda kv: -len(kv[1])):
        print(f'{len(names):5d}  {mod}')

main(sys.argv[1], sys.argv[2])
