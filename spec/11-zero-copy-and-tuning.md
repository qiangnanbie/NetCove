# 11 · 零拷贝渲染与调参流水线

## 11.1 零拷贝链路

```
FFmpeg demux ─► VideoToolbox 硬解 (VTDecompressionSession)
                        │  CVPixelBuffer（IOSurface，Metal 兼容）
                        ▼
              CVMetalTextureCache ──► MTLTexture（**无 CPU 拷贝**）
                        │
                        ▼
          DolbyVisionP5.msl / SDRVideo.msl ──► CAMetalLayer
```

关键文件：

| 文件 | 作用 |
|---|---|
| `Rendering/VideoToolboxDecoder.swift` | `VTDecompressionSession` 配置（`EnableHardwareAcceleratedVideoDecoder`）、`avcC`/`hvcC` → `CMFormatDescription` 解析、异步解码回调 |
| `Rendering/ZeroCopyRenderer.swift` | `CVMetalTextureCache` 建纹理、双平面/单平面/10bit 处理、复用 DV/SDR 管线 |
| `Rendering/MetalVideoRenderer.swift` | 软件解码路径（`replace(region:)` 上传）＋管线状态，两条路径共用着色器 |

回落策略：extradata 是 Annex B（起始码）或解码器拒绝配置时，`vtDecoder = nil`，自动走软解，不影响播放。

10bit 判定：`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange/Full` → `r16Unorm` / `rg16Unorm`。

## 11.2 调参流水线（可勾选、可回填）

```bash
python3 tools/tuning_matrix.py generate          # → spec/tuning/matrix.csv + checklist.md
python3 tools/tuning_matrix.py generate --full   # 全量笛卡尔积
python3 tools/tuning_matrix.py sample            # 示例结果（演示用，非实测）
python3 tools/tuning_matrix.py apply <结果.csv>   # → Sources/NetCovePlayback/EngineTuning.generated.swift
```

矩阵维度：容器(5) × 视频(6) × 帧率(4) × 分辨率(3) × 音频(7) × 字幕(4) × 交互(6)。
精简矩阵当前 **149 条**，其中「预期引擎」列由 `EngineRouter.decide` 同一套规则算出，避免真机跑完才发现分流错了。

必填列：`hardware_decode / startup_ms / dropped_frames / power_mw / verdict`。

判定线（写在 checklist.md 里）：起播 ≤ 1500 ms、掉帧 ≤ 1%、硬解成功、功耗 ≤ 3500 mW。

回填规则（`apply`）：

| 观测 | 生成的参数 |
|---|---|
| 起播 P95 > 1500 ms | `targetByteCount` 8 → 12 MB |
| 起播 P95 > 2500 ms | `targetByteCount` → 16 MB |
| 平均掉帧 > 10 | `playbackCacheByteLimit` → 384 MB |
| 平均掉帧 > 40 | `playbackCacheByteLimit` → 512 MB |
| 硬解率 < 80% | `prewarmEngine = true` |

生成文件带**来源横幅**：若来源文件名含 `sample`，文件头会写明"示例数据，勿当作实测"。

客户端开关：设置 → 播放 → **Use measured tuning**，切换 `EnginePreferences.tuned` / `.default`，
并在下方显示 `tuningSummary`（P95 起播、掉帧、硬解率、失败用例数）。

## 11.3 真机执行建议

1. 先用 `generate` 出矩阵，按容器分组跑（同一批源文件）；
2. 每条只记 4 个数：起播毫秒、掉帧数、是否硬解、功耗（可用 `powermetrics` 或 Xcode Energy 模板）；
3. 跑完 `apply`，在设置里打开 Use measured tuning，重新跑一遍失败用例做回归；
4. 把 `results.csv` 一起提交，方便下次对比。
