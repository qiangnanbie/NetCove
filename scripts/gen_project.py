#!/usr/bin/env python3
"""生成 Xcode 工程，可选剔除第三方 SPM 依赖。

为什么需要这个：NetCove 的第三方库（FFmpeg / libplacebo / KSPlayer / WCDB / sherpa-onnx /
GoogleCast）全部用 `#if canImport` 隔离，所以**不装这些库也能编译**，只是对应功能降级。
CI 先跑无依赖版本，能稳定产出 ipa；依赖版本作为可选 job 单独跑。

用法:
  python3 scripts/gen_project.py                  # 剔除第三方依赖（默认，CI 用）
  python3 scripts/gen_project.py --with-third-party
"""
from __future__ import annotations

import argparse
import copy
import os
import subprocess
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build_spec(with_third_party: bool) -> dict:
    spec = yaml.safe_load(open(os.path.join(ROOT, 'project.yml'), encoding='utf-8'))
    if with_third_party:
        return spec
    spec.pop('packages', None)
    for target in (spec.get('targets') or {}).values():
        deps = [dep for dep in target.get('dependencies', [])
                if not (isinstance(dep, dict) and 'package' in dep)]
        if deps:
            target['dependencies'] = deps
        else:
            target.pop('dependencies', None)
    return spec


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--with-third-party', action='store_true')
    parser.add_argument('--spec-out', default='project.local.yml')
    args = parser.parse_args()

    spec = build_spec(args.with_third_party)
    out_path = os.path.join(ROOT, args.spec_out)
    with open(out_path, 'w', encoding='utf-8') as handle:
        yaml.safe_dump(spec, handle, allow_unicode=True, sort_keys=False)

    mode = 'with third-party' if args.with_third_party else 'no third-party'
    print(f'spec = {args.spec_out} ({mode}); packages={list((spec.get("packages") or {}).keys())}')

    if os.environ.get('SKIP_XCODEGEN') == '1':
        return 0

    try:
        subprocess.run(['xcodegen', 'generate', '--spec', out_path], cwd=ROOT, check=True)
    except FileNotFoundError:
        print('xcodegen 未安装（brew install xcodegen）', file=sys.stderr)
        return 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
