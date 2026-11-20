#!/usr/bin/env python3
"""独立校验 .rexmod：结构 / 规范化摘要 / Ed25519 签名。

用法: python3 tools/verify_module.py <file.rexmod> [--pub Config/dev-signing/module-signing.pub]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile

KNOWN = {'id', 'name', 'version', 'author', 'entry', 'capabilities', 'signature'}


def canonical_manifest(manifest: dict) -> bytes:
    trimmed = {k: v for k, v in manifest.items() if k != 'signature'}
    return json.dumps(trimmed, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False).encode('utf-8')


def digest_of(files: dict[str, bytes], manifest: dict) -> str:
    hasher = hashlib.sha256()
    hasher.update(b'module.json\0')
    hasher.update(canonical_manifest(manifest))
    hasher.update(b'\0')
    for path in sorted(files):
        if path == 'module.json':
            continue
        hasher.update(path.encode())
        hasher.update(b'\0')
        hasher.update(files[path])
        hasher.update(b'\0')
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('package')
    parser.add_argument('--pub', default='Config/dev-signing/module-signing.pub')
    args = parser.parse_args()

    problems: list[str] = []
    with zipfile.ZipFile(args.package) as archive:
        methods = {item.compress_type for item in archive.infolist()}
        if methods - {0}:
            problems.append(f'非 stored 条目: {sorted(methods - {0})}')
        files = {name: archive.read(name) for name in archive.namelist() if not name.endswith('/')}

    if 'module.json' not in files:
        problems.append('缺少 module.json')
        print('\n'.join(problems))
        return 1

    manifest = json.loads(files['module.json'])
    unknown = set(manifest) - KNOWN
    if unknown:
        problems.append(f'未知字段: {sorted(unknown)}')
    for field in ('id', 'name', 'version', 'entry'):
        if not manifest.get(field):
            problems.append(f'缺字段: {field}')
    if manifest.get('entry') and manifest['entry'] not in files:
        problems.append(f'入口脚本不存在: {manifest["entry"]}')

    digest = digest_of(files, manifest)
    print(f'package : {args.package}')
    print(f'id      : {manifest.get("id")} {manifest.get("version")}')
    print(f'entries : {sorted(files)}')
    print(f'digest  : {digest}')

    signature = manifest.get('signature')
    if signature:
        try:
            from cryptography.hazmat.primitives.serialization import load_pem_public_key
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        except ImportError as exc:  # noqa: BLE001
            print(f'signature: 无法校验（缺 cryptography: {exc}）')
        else:
            import base64
            import os
            key_obj = None
            if os.path.exists(args.pub):
                key_obj = load_pem_public_key(open(args.pub, 'rb').read())
            b64_path = args.pub + '.b64'
            if key_obj is None and os.path.exists(b64_path):
                key_obj = Ed25519PublicKey.from_public_bytes(
                    base64.b64decode(open(b64_path).read().strip()))
            if not isinstance(key_obj, Ed25519PublicKey):
                problems.append('公钥不可用')
            else:
                ok = True
                try:
                    key_obj.verify(bytes.fromhex(signature), bytes.fromhex(digest))
                except Exception:  # noqa: BLE001
                    ok = False
                print(f'signature: {"valid" if ok else "INVALID"}')
                if not ok:
                    problems.append('签名校验失败')
    else:
        print('signature: none')

    if problems:
        print('\nFAILED:')
        for problem in problems:
            print('  ✗', problem)
        return 1
    print('\nOK: package valid')
    return 0


if __name__ == '__main__':
    sys.exit(main())
