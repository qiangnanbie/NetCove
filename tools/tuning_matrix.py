#!/usr/bin/env python3
"""播放验收矩阵：生成可勾选的用例表，并把实测结果回填成 Swift 参数文件。

用法：
  python3 tools/tuning_matrix.py generate            # 写 spec/tuning/matrix.csv + checklist.md
  python3 tools/tuning_matrix.py sample              # 写一份示例 results.csv（演示回填）
  python3 tools/tuning_matrix.py apply RESULTS.csv   # 生成 Sources/NetCovePlayback/EngineTuning.generated.swift
"""
from __future__ import annotations

import csv
import itertools
import os
import sys
from dataclasses import dataclass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'spec', 'tuning')

CONTAINERS = ["mp4", "mkv", "ts", "avi", "strm"]
VIDEO_PROFILES = [
    ("h264_8bit_sdr", "SDR", False, None, 0),
    ("hevc_10bit_hdr10", "HDR10", True, None, 0),
    ("dv_p5", "DV", True, 5, 0),
    ("dv_p8", "DV", True, 8, 0),
    ("hlg", "HLG", True, None, 0),
    ("av1_10bit", "HDR10", True, None, 0),
]
FPS = [23.976, 30, 60, 120]
RESOLUTIONS = [(1280, 720), (1920, 1080), (3840, 2160)]
AUDIO = ["aac", "ac3", "eac3", "dts", "truehd", "flac", "opus"]
SUBTITLES = ["none", "srt", "ass", "pgs"]
INTERACTIONS = ["startup", "seek", "rate2x", "audio-switch", "pip", "airplay"]

FIELDS = ["id", "container", "video", "range", "dovi_profile", "fps", "width", "height",
          "audio", "subtitle", "interaction", "expected_engine",
          "hardware_decode", "startup_ms", "dropped_frames", "power_mw", "verdict", "note"]


def expected_engine(container: str, video: str, fps: float, dovi_profile) -> str:
    """与 EngineRouter.decide 同规则：能走系统解码就走 avplayer，否则 ffmpeg"""
    if container not in ("mp4", "m4v", "mov"):
        return "ffmpeg"
    if video.split("_")[0] not in ("h264", "hevc", "av1"):
        return "ffmpeg"
    if dovi_profile == 5:
        return "ffmpeg"
    if fps >= 100:
        return "ffmpeg"
    return "avplayer"


@dataclass
class Case:
    id: str
    container: str
    video: str
    range_name: str
    dovi_profile: object
    fps: float
    width: int
    height: int
    audio: str
    subtitle: str
    interaction: str

    def row(self) -> dict:
        return {
            "id": self.id,
            "container": self.container,
            "video": self.video,
            "range": self.range_name,
            "dovi_profile": "" if self.dovi_profile is None else self.dovi_profile,
            "fps": self.fps,
            "width": self.width,
            "height": self.height,
            "audio": self.audio,
            "subtitle": self.subtitle,
            "interaction": self.interaction,
            "expected_engine": expected_engine(self.container, self.video, self.fps, self.dovi_profile),
            "hardware_decode": "",
            "startup_ms": "",
            "dropped_frames": "",
            "power_mw": "",
            "verdict": "",
            "note": "",
        }


def build_cases(full: bool) -> list[Case]:
    """默认生成精简矩阵（每种组合抽样），full=True 时全量笛卡尔积。"""
    cases: list[Case] = []
    index = 0

    if full:
        combos = itertools.product(CONTAINERS, VIDEO_PROFILES, FPS, RESOLUTIONS, AUDIO, SUBTITLES, INTERACTIONS)
        for container, (video, range_name, _is_hdr, dovi, _flag), fps, (w, h), audio, sub, inter in combos:
            index += 1
            cases.append(Case(f"C{index:04d}", container, video, range_name, dovi,
                              fps, w, h, audio, sub, inter))
        return cases

    # 精简矩阵：关键路径全覆盖（约 240 条）
    for container, (video, range_name, _is_hdr, dovi, _flag) in itertools.product(CONTAINERS, VIDEO_PROFILES):
        for fps, (w, h) in [(23.976, (1920, 1080)), (60, (3840, 2160))]:
            index += 1
            cases.append(Case(f"C{index:04d}", container, video, range_name, dovi,
                              fps, w, h, "aac", "srt", "startup"))
            index += 1
            cases.append(Case(f"C{index:04d}", container, video, range_name, dovi,
                              fps, w, h, "eac3", "ass", "seek"))
    # 帧率 / 分辨率 / 音频 / 字幕 / 交互 单因素扫描（固定 mkv + hevc）
    for fps in FPS:
        for (w, h) in RESOLUTIONS:
            index += 1
            cases.append(Case(f"C{index:04d}", "mkv", "hevc_10bit_hdr10", "HDR10", None,
                              fps, w, h, "aac", "srt", "startup"))
    for audio in AUDIO:
        index += 1
        cases.append(Case(f"C{index:04d}", "mp4", "h264_8bit_sdr", "SDR", None,
                          23.976, 1920, 1080, audio, "none", "audio-switch"))
    for sub in SUBTITLES:
        index += 1
        cases.append(Case(f"C{index:04d}", "mkv", "h264_8bit_sdr", "SDR", None,
                          23.976, 1920, 1080, "aac", sub, "startup"))
    for inter in INTERACTIONS:
        index += 1
        cases.append(Case(f"C{index:04d}", "mp4", "h264_8bit_sdr", "SDR", None,
                          23.976, 1920, 1080, "aac", "srt", inter))
    return cases


def generate(full: bool = False) -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    cases = build_cases(full)
    csv_path = os.path.join(OUT_DIR, 'matrix.csv')
    with open(csv_path, 'w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        for case in cases:
            writer.writerow(case.row())

    md_path = os.path.join(OUT_DIR, 'checklist.md')
    by_container: dict[str, list[Case]] = {}
    for case in cases:
        by_container.setdefault(case.container, []).append(case)

    lines = ["# 播放验收矩阵（自动生成）\n",
             f"共 **{len(cases)}** 条用例。用 `python3 tools/tuning_matrix.py generate --full` 可生成全量笛卡尔积。\n",
             "填完 `matrix.csv` 的 `hardware_decode / startup_ms / dropped_frames / power_mw / verdict` 后，",
             "运行 `python3 tools/tuning_matrix.py apply spec/tuning/matrix.csv` 生成参数文件。\n",
             "**判定线（建议）**：起播 ≤ 1500 ms、掉帧率 ≤ 1%、硬解成功、功耗 ≤ 3500 mW。\n"]
    for container, items in sorted(by_container.items()):
        lines.append(f"\n## {container}（{len(items)} 条）\n")
        lines.append("| id | 视频 | 帧率 | 分辨率 | 音频 | 字幕 | 交互 | 预期引擎 | 结果 |")
        lines.append("|---|---|---|---|---|---|---|---|---|")
        for case in items[:40]:
            lines.append(f"| {case.id} | {case.video} | {case.fps} | {case.width}×{case.height} "
                         f"| {case.audio} | {case.subtitle} | {case.interaction} "
                         f"| {expected_engine(case.container, case.video, case.fps, case.dovi_profile)} | ☐ |")
        if len(items) > 40:
            lines.append(f"\n（其余 {len(items) - 40} 条见 matrix.csv）")
    open(md_path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')

    print(f'generated {len(cases)} cases -> {csv_path}, {md_path}')
    return 0


def sample() -> int:
    """写一份示例结果，用于演示回填链路（数字为示例，不是实测）。"""
    os.makedirs(OUT_DIR, exist_ok=True)
    source = os.path.join(OUT_DIR, 'matrix.csv')
    if not os.path.exists(source):
        generate()
    target = os.path.join(OUT_DIR, 'results.sample.csv')
    with open(source, newline='', encoding='utf-8') as handle:
        rows = list(csv.DictReader(handle))
    for index, row in enumerate(rows):
        hw = "1" if row['expected_engine'] == "avplayer" else "0"
        row['hardware_decode'] = hw
        row['startup_ms'] = str(900 + (index % 5) * 120)
        row['dropped_frames'] = str(index % 3)
        row['power_mw'] = str(1800 + (index % 7) * 90)
        row['verdict'] = "pass" if int(row['startup_ms']) <= 1500 and int(row['dropped_frames']) <= 10 else "fail"
        row['note'] = "sample"
    with open(target, 'w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f'sample results -> {target} ({len(rows)} rows)')
    return 0


def apply(results_path: str) -> int:
    with open(results_path, newline='', encoding='utf-8') as handle:
        rows = list(csv.DictReader(handle))

    def num(row, key, default=0.0) -> float:
        try:
            return float(row.get(key) or default)
        except ValueError:
            return default

    measured = [r for r in rows if r.get('startup_ms')]
    if not measured:
        print('no measured rows (startup_ms empty) — nothing to apply', file=sys.stderr)
        return 1

    startup = sorted(num(r, 'startup_ms') for r in measured)
    p95_startup = startup[int(len(startup) * 0.95) - 1] if len(startup) > 1 else startup[0]
    avg_dropped = sum(num(r, 'dropped_frames') for r in measured) / len(measured)
    hw_success = sum(1 for r in measured if r.get('hardware_decode') == '1') / len(measured)
    p95_power = sorted(num(r, 'power_mw') for r in measured)[int(len(measured) * 0.95) - 1]
    failures = [r for r in measured if r.get('verdict', '').lower() == 'fail']

    # 参数推算：起播慢 → 加大预读；掉帧多 → 加大缓存与预读上限；硬解率低 → 提前预热
    target_bytes = 8
    if p95_startup > 1500:
        target_bytes = 12
    if p95_startup > 2500:
        target_bytes = 16
    max_target = max(target_bytes * 4, 32)
    cache_mb = 256
    if avg_dropped > 10:
        cache_mb = 384
    if avg_dropped > 40:
        cache_mb = 512

    is_sample = 'sample' in os.path.basename(results_path).lower()
    banner = ('⚠️ 本文件由示例数据生成，仅用于演示回填链路；'
              '请在真机上跑完 spec/tuning/matrix.csv 后用真实结果重新生成。') if is_sample else \
             '本文件由真实实测结果生成。'

    generated = f'''//
//  EngineTuning.generated.swift
//  由 tools/tuning_matrix.py 依据实测矩阵生成，请勿手改。
//  来源：{os.path.basename(results_path)}（{len(measured)} 条记录）
//  {banner}
//

import Foundation

extension EnginePreferences {{
    /// 实测回填：起播 P95 {p95_startup:.0f} ms · 平均掉帧 {avg_dropped:.1f} · 硬解率 {hw_success * 100:.0f}% · 功耗 P95 {p95_power:.0f} mW
    static var tuned: EnginePreferences {{
        var preferences = EnginePreferences.default
        preferences.prewarmEngine = {str(hw_success < 0.8).lower()}
        preferences.targetByteCount = {target_bytes} * 1024 * 1024
        preferences.maximumTargetByteCount = {max_target} * 1024 * 1024
        preferences.playbackCacheByteLimit = {cache_mb} * 1024 * 1024
        return preferences
    }}

    /// 未达成判定线的用例数：{len(failures)}
    static var tuningSummary: String {{
        "P95 起播 {p95_startup:.0f} ms · 掉帧 {avg_dropped:.1f} · 硬解 {hw_success * 100:.0f}% · 失败用例 {len(failures)}"
    }}
}}
'''
    target_path = os.path.join(ROOT, 'Sources/NetCovePlayback/EngineTuning.generated.swift')
    open(target_path, 'w', encoding='utf-8').write(generated)
    print(f'applied -> {target_path}')
    print(generated.splitlines()[8])
    return 0


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] == 'generate':
        return generate(full='--full' in args)
    if args[0] == 'sample':
        return sample()
    if args[0] == 'apply' and len(args) > 1:
        return apply(args[1])
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
