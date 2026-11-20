#!/usr/bin/env python3
"""打包/签名脚本模块为 .rexmod（zip）。

用法:
  python3 tools/pack_module.py examples/modules/hello-netcove        # 默认 stored（不压缩）
  python3 tools/pack_module.py <dir> --deflate                       # 用 deflate
  python3 tools/pack_module.py <dir> --sign private.pem              # Ed25519 签名（需 cryptography）

.rexmod 结构：
  module.json      清单（id/name/version/entry/capabilities/signature）
  main.js          入口脚本
  assets/…         可选资源
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import zipfile


def collect(root: str) -> list[str]:
    files = []
    for base, _dirs, names in os.walk(root):
        for name in names:
            full = os.path.join(base, name)
            files.append(os.path.relpath(full, root))
    return sorted(files)


def canonical_manifest(manifest: dict) -> bytes:
    """规范化清单：去掉 signature 字段，键排序、无多余空白、不转义非 ASCII。
    客户端 (Swift) 必须用完全相同的字节序列计算摘要。"""
    trimmed = {k: v for k, v in manifest.items() if k != 'signature'}
    return json.dumps(trimmed, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False).encode('utf-8')


def digest_of(root: str, files: list[str], manifest: dict) -> str:
    """稳定摘要：规范化清单 + 除 module.json 外的所有文件（路径 + 内容）。
    这样签名不会改变被签名的摘要（避免"签完再算一遍"的自指问题）。"""
    hasher = hashlib.sha256()
    hasher.update(b'module.json\0')
    hasher.update(canonical_manifest(manifest))
    hasher.update(b'\0')
    for rel in files:
        if rel.replace(os.sep, '/') == 'module.json':
            continue
        hasher.update(rel.replace(os.sep, '/').encode())
        hasher.update(b'\0')
        with open(os.path.join(root, rel), 'rb') as handle:
            hasher.update(handle.read())
        hasher.update(b'\0')
    return hasher.hexdigest()


def sign_digest(digest_hex: str, key_path: str) -> str:
    try:
        from cryptography.hazmat.primitives.serialization import load_pem_private_key
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError as exc:  # noqa: BLE001
        raise SystemExit(f'--sign 需要 cryptography: {exc}')
    with open(key_path, 'rb') as handle:
        key = load_pem_private_key(handle.read(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise SystemExit('只支持 Ed25519 私钥')
    return key.sign(bytes.fromhex(digest_hex)).hex()


def generate_keypair(out_dir: str) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    os.makedirs(out_dir, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    private_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption())
    public_pem = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo)
    open(os.path.join(out_dir, 'module-signing.key'), 'wb').write(private_pem)
    open(os.path.join(out_dir, 'module-signing.pub'), 'wb').write(public_pem)
    print(f'keypair -> {out_dir}/module-signing.key|pub')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', nargs='?')
    parser.add_argument('--output', '-o', default=None)
    parser.add_argument('--deflate', action='store_true')
    parser.add_argument('--sign', default=None)
    parser.add_argument('--genkey', default=None, help='只生成 Ed25519 密钥对到目录')
    args = parser.parse_args()

    if args.genkey:
        generate_keypair(args.genkey)
        return 0

    if not args.directory:
        parser.error('需要模块目录，或使用 --genkey <输出目录>')
    root = args.directory.rstrip('/')
    manifest_path = os.path.join(root, 'module.json')
    if not os.path.exists(manifest_path):
        raise SystemExit('module.json 缺失')
    manifest = json.load(open(manifest_path, encoding='utf-8'))
    for field in ('id', 'name', 'version', 'entry'):
        if not manifest.get(field):
            raise SystemExit(f'module.json 缺字段: {field}')
    known = {'id', 'name', 'version', 'author', 'entry', 'capabilities', 'signature'}
    unknown = set(manifest) - known
    if unknown:
        raise SystemExit(f'module.json 含未知字段（会让客户端规范化摘要不一致）: {sorted(unknown)}')
    if not os.path.exists(os.path.join(root, manifest['entry'])):
        raise SystemExit(f'入口脚本不存在: {manifest["entry"]}')

    files = collect(root)
    manifest.pop('signature', None)
    digest = digest_of(root, files, manifest)
    if args.sign:
        manifest['signature'] = sign_digest(digest, args.sign)
        json.dump(manifest, open(manifest_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
        # 签名后重算：因为签名不参与摘要，结果必须与签名前的 digest 相同
        digest_after = digest_of(root, files, manifest)
        assert digest_after == digest, 'digest changed after signing — canonicalization bug'
        files = collect(root)

    output = args.output or os.path.join('dist', f'{manifest["id"]}-{manifest["version"]}.rexmod')
    os.makedirs(os.path.dirname(output) or '.', exist_ok=True)
    compression = zipfile.ZIP_DEFLATED if args.deflate else zipfile.ZIP_STORED
    with zipfile.ZipFile(output, 'w', compression=compression) as archive:
        for rel in files:
            archive.write(os.path.join(root, rel), rel.replace(os.sep, '/'))

    print(f'packed {len(files)} files -> {output}')
    print(f'  id={manifest["id"]} version={manifest["version"]} entry={manifest["entry"]}')
    print(f'  sha256={digest}')
    print(f'  signed={"yes" if manifest.get("signature") else "no"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
