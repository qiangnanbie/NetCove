#!/usr/bin/env python3
"""从原 App 二进制提取后端路径表（用于更新 NetCoveCore/Endpoints.swift 与 02-openapi.yaml）。
用法: extract_endpoints.py <MachO 路径>"""
import re, sys, subprocess

def main(binpath):
    text = subprocess.run(['strings', '-a', '-n', '6', binpath],
                          capture_output=True, check=True).stdout.decode('utf-8', 'replace')
    paths = sorted(set(re.findall(r'(?<![\w:])/(?:api|v1|v2|partner)/[A-Za-z0-9_./{}-]+', text)))
    paths = [p for p in paths if len(p) < 120 and 'onnx' not in p]
    for p in paths:
        print(p)
    print(f'# total {len(paths)}', file=sys.stderr)

if __name__ == '__main__':
    main(sys.argv[1])
