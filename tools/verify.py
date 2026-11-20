#!/usr/bin/env python3
"""NetCove 静态自检：结构、括号、契约一致性、文案一致性、付费墙残留、必交付文件。

用法: python3 tools/verify.py          # 在 NetCove 根目录跑
退出码 0 = 全部通过。
"""
from __future__ import annotations

import glob
import os
import re
import sys
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
issues: list[str] = []
notes: list[str] = []


def strip_code(text: str) -> str:
    """去掉字符串字面量与注释，避免括号计数被误伤。"""
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
            # Swift 多行字符串：跳到成对的 """
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


def check_braces() -> None:
    files = sorted(glob.glob(os.path.join(ROOT, 'Sources', '**', '*.swift'), recursive=True))
    for path in files:
        code = strip_code(open(path, encoding='utf-8').read())
        for opener, closer, label in (('{', '}', 'braces'), ('(', ')', 'parens'), ('[', ']', 'brackets')):
            if code.count(opener) != code.count(closer):
                issues.append(f"{os.path.relpath(path, ROOT)}: {label} unbalanced "
                              f"({code.count(opener)}/{code.count(closer)})")
    notes.append(f"swift files checked: {len(files)}")


def check_project_paths() -> None:
    path = os.path.join(ROOT, 'project.yml')
    if not os.path.exists(path):
        issues.append('project.yml missing')
        return
    try:
        import yaml
        config = yaml.safe_load(open(path))
    except Exception as exc:  # noqa: BLE001
        issues.append(f'project.yml unparseable: {exc}')
        return
    for target_name, target in (config.get('targets') or {}).items():
        for source in target.get('sources', []):
            rel = source if isinstance(source, str) else source.get('path')
            if not rel:
                continue
            if not os.path.exists(os.path.join(ROOT, rel)):
                issues.append(f'{target_name}: source path missing -> {rel}')
        plist = (target.get('settings') or {}).get('base', {}).get('INFOPLIST_FILE')
        if plist and not os.path.exists(os.path.join(ROOT, plist)):
            issues.append(f'{target_name}: Info.plist missing -> {plist}')
    notes.append('project.yml paths verified')


def client_endpoints() -> set[str]:
    text = open(os.path.join(ROOT, 'Sources/NetCoveCore/Endpoints.swift'), encoding='utf-8').read()
    return set(re.findall(r'return "(/[^"]+)"', text))


def check_contract() -> None:
    spec_path = os.path.join(ROOT, 'spec/02-openapi.yaml')
    try:
        import yaml
        spec = yaml.safe_load(open(spec_path))
    except Exception as exc:  # noqa: BLE001
        issues.append(f'openapi unparseable: {exc}')
        return
    spec_paths = set(spec.get('paths', {}).keys())
    client = client_endpoints()
    missing = sorted(client - spec_paths)
    if missing:
        issues.append(f'client endpoints absent from openapi: {missing}')
    notes.append(f'openapi paths: {len(spec_paths)}, client endpoints: {len(client)}')


def keys_of(path: str) -> set[str]:
    text = open(path, encoding='utf-8').read()
    return set(re.findall(r'^"([^"]+)"\s*=', text, re.M))


def pairs_of(path: str) -> dict[str, str]:
    text = open(path, encoding='utf-8').read()
    return dict(re.findall(r'^"([^"]+)"\s*=\s*"(.*)";\s*$', text, re.M))


def check_localization() -> None:
    en = keys_of(os.path.join(ROOT, 'Resources/en.lproj/Localizable.strings'))
    for lproj in sorted(glob.glob(os.path.join(ROOT, 'Resources', '*.lproj'))):
        lang = os.path.basename(lproj)
        zh = keys_of(os.path.join(lproj, 'Localizable.strings'))
        if zh != en:
            only_lang = sorted(zh - en)
            only_en = sorted(en - zh)
            if only_lang or only_en:
                issues.append(f'{lang}: key mismatch (extra={only_lang[:5]}, missing={only_en[:5]})')
    notes.append(f'localization keys: {len(en)}')


def check_paywall() -> None:
    banned = ['LicenseGate', 'PointsLedger', 'AppAttest', 'DCAppAttestService',
              'playbackLease', 'pointsBalance', 'paid.playback', 'featureGate']
    hits = []
    for path in glob.glob(os.path.join(ROOT, 'Sources', '**', '*.swift'), recursive=True):
        text = open(path, encoding='utf-8').read()
        for token in banned:
            if token in text:
                hits.append(f'{os.path.relpath(path, ROOT)}: {token}')
    if hits:
        issues.append(f'paywall leftovers: {hits}')
    else:
        notes.append('no paywall leftovers')


def check_required_files() -> None:
    required = [
        'README.md', 'project.yml', 'Config/Info.plist',
        'Server/netcove_server.py',
        'spec/01-architecture.md', 'spec/02-openapi.yaml', 'spec/03-authorization.md',
        'spec/04-playback-tuning.md', 'spec/05-type-inventory.md', 'spec/06-gap-analysis.md',
        'spec/07-cloudkit.md', 'spec/08-server.md',
        'Resources/Assets.xcassets/AppIcon.appiconset/Contents.json',
    ]
    for rel in required:
        if not os.path.exists(os.path.join(ROOT, rel)):
            issues.append(f'missing deliverable: {rel}')
    notes.append(f'required files: {len(required)}')


def check_shaders() -> None:
    shaders = ['DolbyVisionP5.msl', 'SDRVideo.msl', 'Danmaku.msl']
    base = os.path.join(ROOT, 'Sources/NetCovePlayback/Rendering/Shaders')
    for name in shaders:
        path = os.path.join(base, name)
        if not os.path.exists(path):
            issues.append(f'missing shader: {name}')
            continue
        text = open(path, encoding='utf-8').read()
        if 'vertex ' not in text or 'fragment ' not in text:
            issues.append(f'{name}: missing vertex/fragment entry')
    notes.append(f'shaders: {len(shaders)}')


def check_localization_coverage() -> None:
    en = pairs_of(os.path.join(ROOT, 'Resources/en.lproj/Localizable.strings'))
    rows = []
    for lproj in sorted(glob.glob(os.path.join(ROOT, 'Resources', '*.lproj'))):
        lang = os.path.basename(lproj).replace('.lproj', '')
        if lang == 'en':
            continue
        table = pairs_of(os.path.join(lproj, 'Localizable.strings'))
        same = sum(1 for k, v in table.items() if v == en.get(k))
        covered = len(table) - same
        rows.append(f'{lang}={covered}/{len(table)}' + (f'(+{same} 同形词)' if same else ''))
    notes.append('i18n: ' + ', '.join(rows))


def check_tuning() -> None:
    matrix = os.path.join(ROOT, 'spec/tuning/matrix.csv')
    generated = os.path.join(ROOT, 'Sources/NetCovePlayback/EngineTuning.generated.swift')
    if not os.path.exists(matrix):
        issues.append('missing spec/tuning/matrix.csv (run tools/tuning_matrix.py generate)')
    else:
        with open(matrix, encoding='utf-8') as handle:
            rows = sum(1 for _ in handle) - 1
        if rows < 50:
            issues.append(f'tuning matrix too small: {rows} rows')
        else:
            notes.append(f'tuning matrix rows: {rows}')
    if not os.path.exists(generated):
        issues.append('missing EngineTuning.generated.swift (run tools/tuning_matrix.py apply)')
    else:
        notes.append('tuning params generated')


def check_module_pipeline() -> None:
    module_dir = os.path.join(ROOT, 'examples/modules/hello-netcove')
    manifest = os.path.join(module_dir, 'module.json')
    if not os.path.exists(manifest):
        issues.append('missing example module manifest')
    else:
        import json
        try:
            data = json.load(open(manifest))
            for field in ('id', 'name', 'version', 'entry'):
                if not data.get(field):
                    issues.append(f'example module.json missing field: {field}')
            if not os.path.exists(os.path.join(module_dir, data.get('entry', 'main.js'))):
                issues.append('example module entry script missing')
        except Exception as exc:  # noqa: BLE001
            issues.append(f'example module.json unparseable: {exc}')
    if not os.path.exists(os.path.join(ROOT, 'tools/pack_module.py')):
        issues.append('missing tools/pack_module.py')
    built = glob.glob(os.path.join(ROOT, 'examples/dist/*.rexmod'))
    if not built:
        issues.append('no built .rexmod in examples/dist (run tools/pack_module.py)')
    else:
        notes.append(f'rexmod built: {os.path.basename(built[0])}')


def check_release_artifacts() -> None:
    import plistlib

    # 1) 隐私清单
    privacy_path = os.path.join(ROOT, 'Resources/PrivacyInfo.xcprivacy')
    if not os.path.exists(privacy_path):
        issues.append('missing PrivacyInfo.xcprivacy')
    else:
        try:
            privacy = plistlib.load(open(privacy_path, 'rb'))
            if privacy.get('NSPrivacyTracking') is not False:
                issues.append('PrivacyInfo: NSPrivacyTracking must be false')
            if not privacy.get('NSPrivacyAccessedAPITypes'):
                issues.append('PrivacyInfo: no accessed API types declared')
            notes.append(f'privacy: {len(privacy.get("NSPrivacyAccessedAPITypes", []))} API categories')
        except Exception as exc:  # noqa: BLE001
            issues.append(f'PrivacyInfo unparseable: {exc}')

    # 2) 授权文件
    ent_path = os.path.join(ROOT, 'Config/NetCove.entitlements')
    if not os.path.exists(ent_path):
        issues.append('missing Config/NetCove.entitlements')
    else:
        try:
            ent = plistlib.load(open(ent_path, 'rb'))
            if not ent.get('com.apple.developer.icloud-container-identifiers'):
                issues.append('entitlements: missing iCloud container')
            if not ent.get('com.apple.security.application-groups'):
                issues.append('entitlements: missing app group')
        except Exception as exc:  # noqa: BLE001
            issues.append(f'entitlements unparseable: {exc}')

    # 3) 导出配置
    if not os.path.exists(os.path.join(ROOT, 'Config/ExportOptions.plist')):
        issues.append('missing Config/ExportOptions.plist')

    # 4) 图标完整性
    import json
    icon_dir = os.path.join(ROOT, 'Resources/Assets.xcassets/AppIcon.appiconset')
    manifest_path = os.path.join(icon_dir, 'Contents.json')
    if not os.path.exists(manifest_path):
        issues.append('missing AppIcon Contents.json')
    else:
        entries = json.load(open(manifest_path))['images']
        missing = [entry['filename'] for entry in entries
                   if entry.get('filename') and not os.path.exists(os.path.join(icon_dir, entry['filename']))]
        if missing:
            issues.append(f'missing icon files: {missing[:3]}')
        if not any(entry.get('size') == '1024x1024' for entry in entries):
            issues.append('AppIcon: no 1024x1024 marketing icon')
        notes.append(f'icons: {len(entries)} entries')

    # 5) 启动画面
    for name in ('LaunchMark.imageset', 'LaunchBackground.colorset'):
        if not os.path.exists(os.path.join(ROOT, 'Resources/Assets.xcassets', name)):
            issues.append(f'missing launch asset: {name}')

    # 6) Info.plist 关键键
    info = plistlib.load(open(os.path.join(ROOT, 'Config/Info.plist'), 'rb'))
    for key in ('NetCoveModuleKey', 'UILaunchScreen', 'CFBundleURLTypes', 'NSBonjourServices'):
        if key not in info:
            issues.append(f'Info.plist missing {key}')

    # 7) 单元测试与脚本
    tests = glob.glob(os.path.join(ROOT, 'Tests/NetCoveTests/*.swift'))
    if len(tests) < 5:
        issues.append(f'too few test files: {len(tests)}')
    else:
        notes.append(f'tests: {len(tests)} files')
    for script in ('scripts/ci.sh', 'scripts/release.sh'):
        path = os.path.join(ROOT, script)
        if not os.path.exists(path):
            issues.append(f'missing {script}')
        elif not os.access(path, os.X_OK):
            issues.append(f'{script} not executable')


def check_alignment() -> None:
    # 依赖声明
    import yaml
    config = yaml.safe_load(open(os.path.join(ROOT, 'project.yml')))
    packages = set((config.get('packages') or {}).keys())
    expected = {'KSPlayer', 'Alamofire', 'Nuke', 'AMSMB2', 'WCDB'}
    missing = expected - packages
    if missing:
        issues.append(f'project.yml 缺少依赖声明: {sorted(missing)}')
    else:
        notes.append(f'dependencies declared: {len(packages)} SPM packages')

    target_deps = config['targets']['NetCove'].get('dependencies', [])
    if not any('package' in (dep if isinstance(dep, dict) else {}) for dep in target_deps):
        issues.append('app target 未引用任何 SPM package')

    # 模块边界报告
    if not os.path.exists(os.path.join(ROOT, 'spec/module-boundaries.md')):
        issues.append('missing spec/module-boundaries.md (run tools/module_map.py --write)')

    # 持久化抽象与 WCDB 实现
    for rel in ('Sources/NetCoveData/Persistence.swift', 'Sources/NetCoveData/WCDBPersistence.swift'):
        if not os.path.exists(os.path.join(ROOT, rel)):
            issues.append(f'missing {rel}')


def check_server() -> None:
    path = os.path.join(ROOT, 'Server/netcove_server.py')
    try:
        import ast
        ast.parse(open(path, encoding='utf-8').read())
    except Exception as exc:  # noqa: BLE001
        issues.append(f'server syntax error: {exc}')
    text = open(path, encoding='utf-8').read()
    served = set(re.findall(r'path == "([^"]+)"', text))
    client = client_endpoints()
    covered = sorted(p for p in client if p in served)
    notes.append(f'server routes: {len(served)}, client endpoints served: {len(covered)}/{len(client)}')


def main() -> int:
    check_braces()
    check_project_paths()
    check_contract()
    check_localization()
    check_paywall()
    check_required_files()
    check_shaders()
    check_localization_coverage()
    check_tuning()
    check_module_pipeline()
    check_release_artifacts()
    check_alignment()
    check_server()

    print('== notes ==')
    for note in notes:
        print('  -', note)
    print('== issues ==')
    if issues:
        for issue in issues:
            print('  ✗', issue)
        print(f'\nFAILED: {len(issues)} issue(s)')
        return 1
    print('  (none)')
    print('\nOK: all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
