#!/usr/bin/env python3
"""NetCove 一致性审计：找编译级错误与文档不实之处。

检查项：
  A. Endpoint 的三处 switch（path / method / isAuthDomain）是否覆盖全部 case —— 缺 case 会编译失败
  B. 项目自有类型被引用但未定义（按命名后缀识别，排除系统类型）
  C. 已定义但从未被引用的类型（死代码线索，仅提示）
  D. SwiftUI 中 NavigationLink / sheet 指向的 View 是否存在
  E. 文档里的数字（矩阵行数、测试文件数等）与实际是否一致

用法: python3 tools/audit.py [--strict]
退出码 1 = 存在 error 级问题。
"""
from __future__ import annotations

import collections
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUFFIXES = ("Store", "Manager", "Runtime", "View", "Engine", "Panel", "Renderer", "Atlas",
            "Scheduler", "Client", "Provider", "Repository", "Bridge", "Service", "Pipeline",
            "Result", "Descriptor", "Manifest", "Uniforms", "Session", "Controller",
            "Coordinator", "Bridging", "Package", "Gate", "Lock", "Ledger", "Matcher",
            "Scanner", "Parser", "Detector", "Writer", "Reader", "Info", "Probe", "Preferences")

SYSTEM_TYPES = {
    # Foundation / Swift 标准库
    'AnyCancellable', 'AnyObject', 'Array', 'Bool', 'Calendar', 'Character', 'CodingKey',
    'Data', 'Date', 'DateFormatter', 'Decimal', 'Dictionary', 'Double', 'Encoder', 'Error',
    'FileManager', 'Float', 'HTTPURLResponse', 'Int', 'JSONDecoder', 'JSONEncoder',
    'JSONSerialization', 'Locale', 'LocalizedError', 'NSLog', 'NSPredicate', 'NSNumber',
    'OperationQueue', 'Optional', 'Result', 'Scanner', 'SecKey', 'Set', 'String',
    'TimeInterval', 'URL', 'URLComponents', 'URLQueryItem', 'URLRequest', 'URLResponse',
    'URLSession', 'URLSessionConfiguration', 'UserDefaults', 'UUID', 'Void',
    # SwiftUI
    'AnyView', 'AsyncImage', 'Binding', 'Button', 'Color', 'ContentUnavailableView',
    'EmptyView', 'Environment', 'EnvironmentObject', 'ForEach', 'Form', 'Group', 'HStack',
    'Image', 'Label', 'LabeledContent', 'LinearGradient', 'List', 'Menu', 'NavigationLink',
    'NavigationStack', 'Picker', 'ProgressView', 'RoundedRectangle', 'ScrollView',
    'Section', 'SecureField', 'Spacer', 'State', 'StateObject', 'TabView', 'Text',
    'TextField', 'Toggle', 'ToolbarItem', 'VStack', 'View', 'ZStack',
    # UIKit / AV / Metal / Core*
    'AVPlayer', 'AVPlayerItem', 'AVPlayerLayer', 'AVRoutePickerView', 'AVURLAsset', 'AVAssetReader',
    'AVAssetReaderTrackOutput', 'AVURLAssetPreferPreciseDurationAndTimingKey',
    'CAMetalDrawable', 'CAMetalLayer', 'CGColorSpace', 'CGColorSpaceCreateDeviceRGB',
    'CGContext', 'CGImage', 'CGImageAlphaInfo', 'CGRect', 'CGSize', 'CMBlockBuffer',
    'CMSampleBuffer', 'CMSampleTimingInfo', 'CMTime', 'CMTimeScale', 'CMVideoFormatDescription',
    'CMVideoFormatDescriptionCreateFromH264ParameterSets',
    'CMVideoFormatDescriptionCreateFromHEVCParameterSets', 'CVPixelBuffer',
    'CVPixelBufferGetHeight', 'CVPixelBufferGetPixelFormatType', 'CVPixelBufferGetPlaneCount',
    'CVPixelBufferGetWidth', 'CVPixelBufferGetHeightOfPlane', 'CVPixelBufferGetWidthOfPlane',
    'CVMetalTexture', 'CVMetalTextureCache', 'CVMetalTextureGetTexture',
    'CVMetalTextureCacheCreate', 'CVMetalTextureCacheCreateTextureFromImage',
    'CVMetalTextureCacheFlush', 'CTLine', 'CTLineCreateWithAttributedString',
    'CTLineDraw', 'CTLineGetBoundsWithOptions',
    'LAContext', 'MTLCommandQueue', 'MTLDevice', 'MTLLibrary', 'MTLPixelFormat',
    'MTLRenderPassDescriptor', 'MTLRenderPipelineDescriptor', 'MTLRenderPipelineState',
    'MTLTexture', 'MTLTextureDescriptor', 'MTKView', 'NSAttributedString',
    'SFSpeechRecognizer', 'SFSpeechURLRecognitionRequest', 'SHA256', 'UIFont', 'UIColor',
    'UIImage', 'UIView', 'UITextContentType', 'UIViewRepresentable', 'UTType',
    'VTDecompressionSession', 'VTDecompressionSessionCreate', 'VTDecompressionSessionDecodeFrame',
    'VTDecompressionSessionInvalidate', 'VTDecompressionSessionWaitForAsynchronousFrames',
    'VTSessionCopyProperty', 'VTDecodeFrameFlags', 'VTDecodeInfoFlags',
    'CKContainer', 'CKDatabase', 'CKError', 'CKFetchRecordZoneChangesOperation', 'CKQuery',
    'CKRecord', 'CKRecordZone', 'CKServerChangeToken', 'Curve25519',
    'JSContext', 'JSValue', 'SecRandomCopyBytes',
    # AMSMB2（可选依赖）
    'SMBManager', 'SMBCredential',
    # Foundation Bonjour
    'NetService', 'NetServiceBrowser', 'NetServiceBrowserDelegate', 'NetServiceDelegate',
}

errors: list[str] = []
warnings: list[str] = []
notes: list[str] = []


def swift_files(include_tests: bool = True) -> list[str]:
    pattern = ['Sources/**/*.swift']
    if include_tests:
        pattern.append('Tests/**/*.swift')
    files: list[str] = []
    for item in pattern:
        files += glob.glob(os.path.join(ROOT, item), recursive=True)
    return sorted(files)


def strip_comments_keep_strings(text: str) -> str:
    """只去注释，保留字符串内容（用于统计 return "/path" 之类）"""
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
        else:
            out.append(c)
            i += 1
    return ''.join(out)


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


# ---------------------------------------------------------------- A. Endpoint switch 覆盖

def check_endpoint_switches() -> None:
    path = os.path.join(ROOT, 'Sources/NetCoveCore/Endpoints.swift')
    if not os.path.exists(path):
        errors.append('Endpoints.swift missing')
        return

    raw = strip_comments_keep_strings(open(path, encoding='utf-8').read())
    code = strip_comments(raw)

    # 1) 声明了哪些 case（含同行多 case）
    declared: set[str] = set()
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith('case ') and not stripped.startswith('case .'):
            for name in (part.strip() for part in stripped[5:].split(',')):
                if re.fullmatch(r'\w+', name):
                    declared.add(name)
    if not declared:
        errors.append('Endpoints.swift: 未解析到任何 case')
        return

    def block_of(marker: str) -> str:
        if marker not in code:
            return ''
        block = code.split(marker, 1)[1]
        depth, out = 1, []
        for character in block:
            if character == '{':
                depth += 1
            elif character == '}':
                depth -= 1
                if depth == 0:
                    break
            out.append(character)
        return ''.join(out)

    def covered_in(marker: str) -> tuple[set[str], bool]:
        block = block_of(marker)
        if not block:
            return set(), False
        if re.search(r'^\s*default\s*:', block, re.M):
            return set(declared), True
        found: set[str] = set()
        for match in re.finditer(r'case ((?:\.\w+\s*,?\s*)+):', block):
            found.update(re.findall(r'\.(\w+)', match.group(1)))
        return found, False

    for label, marker in (('path', 'var path: String {'),
                          ('method', 'var method: String {'),
                          ('isAuthDomain', 'var isAuthDomain: Bool {')):
        covered, has_default = covered_in(marker)
        if not covered and not has_default:
            errors.append(f'Endpoint.{label}: switch 未找到或为空')
            continue
        missing = sorted(declared - covered)
        if missing:
            errors.append(f'Endpoint.{label} 缺 case（会编译失败）: {missing}')
        else:
            suffix = ' (default 覆盖)' if has_default else ''
            notes.append(f'Endpoint.{label}: {len(covered)}/{len(declared)} cases covered{suffix}')

    returns = len(re.findall(r'return "/', raw))
    if returns != len(declared):
        errors.append(f'Endpoint.path 返回 {returns} 条，但声明了 {len(declared)} 个 case')


# ---------------------------------------------------------------- B/C. 类型定义 vs 引用

def collect_definitions(files: list[str]) -> dict[str, list[str]]:
    definitions: dict[str, list[str]] = collections.defaultdict(list)
    pattern = re.compile(r'^\s*(?:public |private |internal |fileprivate |static )?'
                         r'(?:final )?(struct|class|enum|actor|protocol|typealias) (\w+)', re.M)
    for path in files:
        code = strip_comments(open(path, encoding='utf-8').read())
        for kind, name in pattern.findall(code):
            definitions[name].append(os.path.relpath(path, ROOT))
    return definitions


def check_type_references() -> None:
    files = swift_files()
    definitions = collect_definitions(files)
    known = set(definitions)

    # 收集所有引用（粗略：标识符），只关心带项目后缀的名字
    referenced: collections.Counter = collections.Counter()
    for path in files:
        code = strip_comments(open(path, encoding='utf-8').read())
        for identifier in re.findall(r'\b[A-Z][A-Za-z0-9_]{2,}\b', code):
            referenced[identifier] += 1

    unresolved = sorted(
        name for name in referenced
        if name not in known
        and name not in SYSTEM_TYPES
        and name.endswith(SUFFIXES)
        # 系统框架前缀（NS/AV/MTL/...）与可选 SDK（GCK = Google Cast）不参与判定
        and not name.startswith(('NS', 'AV', 'MTL', 'CV', 'CM', 'VT', 'CK', 'LA', 'CT', 'SF',
                                 'GCK', 'WCDB', 'SMB', 'KS'))
    )
    if unresolved:
        for name in unresolved:
            sample = [os.path.relpath(p, ROOT) for p in files
                      if re.search(rf'\b{name}\b', strip_comments(open(p, encoding='utf-8').read()))][:2]
            errors.append(f'引用了未定义的类型: {name} (in {sample})')
    else:
        notes.append(f'类型引用: {len(known)} 个自有类型全部有定义')

    # 忽略 XCTest 用例与 @main 入口（它们不需要被别处引用）
    ignored = {name for name in definitions if name.endswith('Tests')}
    for name in list(definitions):
        for file_path in definitions[name]:
            body = open(os.path.join(ROOT, file_path), encoding='utf-8').read()
            if re.search(rf'@main\b[\s\S]{{0,80}}struct {name}\b', body):
                ignored.add(name)

    # 死代码线索：定义但从未被引用
    unused = []
    for name in definitions:
        if name in ignored:
            continue
        total = sum(len(re.findall(rf'\b{name}\b',
                                   strip_comments(open(path, encoding='utf-8').read())))
                    for path in files)
        if total < 2:
            unused.append(name)
    if unused:
        warnings.append(f'可能未被使用的类型（仅提示）: {sorted(unused)[:12]}')


# ---------------------------------------------------------------- D. SwiftUI 目的地

def check_navigation_targets() -> None:
    files = glob.glob(os.path.join(ROOT, 'Sources/NetCoveApp/*.swift'))
    view_defs = set()
    for path in files:
        code = open(path, encoding='utf-8').read()
        view_defs |= set(re.findall(r'struct (\w+):\s*View\b', code))
    missing = []
    for path in files:
        code = open(path, encoding='utf-8').read()
        for target in re.findall(r'(?:NavigationLink|NavigationLink\()[\s\S]{0,80}?\{\s*(\w+View)\s*\(', code):
            if target not in view_defs:
                missing.append(f'{os.path.basename(path)} -> {target}')
    if missing:
        errors.append(f'NavigationLink 指向未定义的 View: {missing}')
    else:
        notes.append(f'导航目的地: {len(view_defs)} 个 View 定义全部可解析')


# ---------------------------------------------------------------- E. 文档数字一致性

def check_doc_claims() -> None:
    matrix = os.path.join(ROOT, 'spec/tuning/matrix.csv')
    rows = 0
    if os.path.exists(matrix):
        with open(matrix, encoding='utf-8') as handle:
            rows = sum(1 for _ in handle) - 1
    tests = len(glob.glob(os.path.join(ROOT, 'Tests/NetCoveTests/*.swift')))
    swift = len(glob.glob(os.path.join(ROOT, 'Sources/**/*.swift'), recursive=True)) \
        + len(glob.glob(os.path.join(ROOT, 'Tests/**/*.swift'), recursive=True))

    checks = {
        'spec/06-gap-analysis.md': None,
        'spec/13-release.md': None,
        'README.md': None,
    }
    for rel in checks:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        text = open(path, encoding='utf-8').read()
        for claimed in re.findall(r'(\d+)\s*条用例', text):
            if int(claimed) != rows:
                errors.append(f'{rel}: 声称 {claimed} 条用例，实际 {rows}')
        for claimed in re.findall(r'(\d+)\s*个测试文件', text):
            if int(claimed) != tests:
                errors.append(f'{rel}: 声称 {claimed} 个测试文件，实际 {tests}')
        for claimed in re.findall(r'(\d+)\s*个 Swift 文件', text):
            if int(claimed) != swift:
                errors.append(f'{rel}: 声称 {claimed} 个 Swift 文件，实际 {swift}')
    notes.append(f'文档数字: 矩阵 {rows} 行 / 测试 {tests} 文件 / 源码 {swift} 文件')


def main() -> int:
    strict = '--strict' in sys.argv
    check_endpoint_switches()
    check_type_references()
    check_navigation_targets()
    check_doc_claims()

    print('== notes ==')
    for note in notes:
        print('  -', note)
    print('== warnings ==')
    for warning in warnings or ['(none)']:
        print('  !', warning)
    print('== errors ==')
    for error in errors or ['(none)']:
        print('  ✗', error)
    if errors:
        print(f'\nFAILED: {len(errors)} error(s)')
        return 1
    print('\nOK: audit passed')
    return 1 if (strict and warnings) else 0


if __name__ == '__main__':
    sys.exit(main())
