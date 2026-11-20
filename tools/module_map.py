#!/usr/bin/env python3
"""模块边界分析：为「按 Rex 拆成多模块」准备可执行的 public API 清单。

Rex 的一方模块是 26 个独立 framework；NetCove 现在是单 target 的 5 个目录。
要拆分，每个跨目录引用的类型/成员都必须 public。这个脚本把这份清单算出来。

用法: python3 tools/module_map.py [--write]   # --write 输出 spec/module-boundaries.md
"""
from __future__ import annotations

import collections
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODULES = {
    'NetCoveCore': 'Sources/NetCoveCore',
    'NetCoveData': 'Sources/NetCoveData',
    'NetCovePlayback': 'Sources/NetCovePlayback',
    'NetCoveScript': 'Sources/NetCoveScript',
    'NetCoveApp': 'Sources/NetCoveApp',
}

# 计划中的依赖方向（下层被上层依赖）
DEPENDENCIES = {
    'NetCoveCore': [],
    'NetCoveData': ['NetCoveCore'],
    'NetCovePlayback': ['NetCoveCore', 'NetCoveData'],
    'NetCoveScript': ['NetCoveCore'],
    'NetCoveApp': ['NetCoveCore', 'NetCoveData', 'NetCovePlayback', 'NetCoveScript'],
}

# 只统计文件作用域声明（行首无缩进）——嵌套类型不构成模块 API
DECL = re.compile(r'^(?:@\w+\s+)?(?:public |private |internal |fileprivate )?'
                  r'(?:final )?(struct|class|enum|actor|protocol|typealias) (\w+)', re.M)


def strip_comments(text: str) -> str:
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                i += 1
            i += 2
        elif text.startswith('"""', i):
            i += 3
            while i + 2 < n and not text.startswith('"""', i):
                i += 1
            i += 3
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\':
                    i += 1
                i += 1
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def main() -> int:
    owner: dict[str, str] = {}
    for module, folder in MODULES.items():
        for path in glob.glob(os.path.join(ROOT, folder, '**', '*.swift'), recursive=True):
            code = strip_comments(open(path, encoding='utf-8').read())
            for _kind, name in DECL.findall(code):
                owner.setdefault(name, module)

    needs: dict[tuple[str, str], set[str]] = collections.defaultdict(set)
    for module, folder in MODULES.items():
        for path in glob.glob(os.path.join(ROOT, folder, '**', '*.swift'), recursive=True):
            code = strip_comments(open(path, encoding='utf-8').read())
            for identifier in set(re.findall(r'\b[A-Z][A-Za-z0-9_]+\b', code)):
                source = owner.get(identifier)
                if source and source != module:
                    needs[(module, source)].add(identifier)

    lines = ['# 模块边界（拆分前的 public API 清单）\n',
             'Rex 的一方模块是 26 个独立 framework；NetCove 目前是单 target 的 5 个目录。',
             '要拆成多模块，下表列出的每个类型及其被引用的成员都必须标记 `public`。\n']
    total = 0
    for (consumer, provider), names in sorted(needs.items()):
        total += len(names)
        lines.append(f'## {provider} → {consumer}（{len(names)} 个类型需 public）\n')
        lines.append('```')
        lines.extend(sorted(names))
        lines.append('```\n')

    # 依赖方向检查
    lines.append('## 依赖方向\n')
    for module, deps in DEPENDENCIES.items():
        lines.append(f'- `{module}` → {", ".join("`" + d + "`" for d in deps) or "（无）"}')
    violations = [(c, p) for (c, p) in needs if p not in DEPENDENCIES.get(c, [])]
    lines.append('\n## 违背依赖方向（必须处理）\n')
    if violations:
        for consumer, provider in violations:
            lines.append(f'- ⚠️ `{consumer}` 依赖了未声明的 `{provider}`')
    else:
        lines.append('- 无（当前引用方向与计划一致）')

    report = '\n'.join(lines) + '\n'
    print(f'跨模块引用类型总数: {total}')
    for (consumer, provider), names in sorted(needs.items()):
        print(f'  {provider:16} -> {consumer:16} {len(names):3} 类型')
    print('依赖方向违规:', violations or '无')

    if '--write' in sys.argv:
        out = os.path.join(ROOT, 'spec/module-boundaries.md')
        open(out, 'w', encoding='utf-8').write(report)
        print('written ->', out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
