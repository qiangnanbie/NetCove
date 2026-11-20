# 04 · 播放内核与调参清单

这是全项目最难、也最决定"像不像"的一块。原 App 暴露的参数名已抄进 `EnginePreferences`，但**取值只能真机实测**。

## 4.1 引擎分工

| 路线 | 用于 | 关键点 |
|---|---|---|
| AVPlayer 路线（KSPlayer 壳） | 常规 MP4/H.264/HEVC、AirPlay、PiP、外接屏 | 系统解码器，功耗低，HDR 走系统 tone mapping |
| FFmpeg 路线（自编 Libav*） | MKV/AVI/TS、Dolby Vision、缺系统解码器的编码 | 软件/硬件混合解码 + libplacebo 渲染 |

判定分流：容器是否 MP4、是否 DV、是否 4K/120fps、音频是否需重采样（libswresample）。

## 4.2 参数对照（照抄字段名，取值需实测）

| 字段 | 含义 | 建议起点 |
|---|---|---|
| `prewarmEngine` | 进详情页就预热解码器 | `true` |
| `targetByteCount` | 起播前预读字节 | 8 MB |
| `maximumTargetByteCount` | 自适应上限 | 32 MB |
| `playbackCacheByteLimit` | 播放缓存上限 | 256 MB |
| `minimumAdoptionProgress` | 采纳新码率所需最小缓冲进度 | 0.35 |
| `maximumPreparedAge` | prepared 资源最长存活 | 30 s |
| `resourceExpirationSafetyInterval` | 过期前安全余量 | 20 s |
| `creditsLeadTime` | 片头跳过提前量 | 3 s |
| `endGuard` | 片尾保护区 | 12 s |
| `noCreditsTriggerFraction` | 无片头判定阈值 | 0.92 |

## 4.3 Dolby Vision 要点

- Profile 5：无回退层，**必须**按 IPTPQc2 解码并做色彩变换，否则偏紫/偏绿；
- Profile 8.1/8.4：有 HDR10/HLG 回退层，可降级播放；
- 元数据矩阵转换（原 App 用 `DoviMatrix` + `libdovi`）：RPU 解析、level 5/6 裁剪；
- 需要 `SUPPLEMENTAL-CODECS=dvh1/db4h` 这类声明（原 App 的 m3u8 侧就是这么写的）。

## 4.4 验收矩阵（缺一不可）

| 维度 | 用例 |
|---|---|
| 容器 | MP4 / MKV / TS / AVI / STRM |
| 视频 | H.264 8bit、HEVC 10bit、AV1、DV P5、DV P8、HDR10、HLG |
| 帧率 | 23.976 / 30 / 60 / 120 |
| 分辨率 | 720p / 1080p / 4K / 8K 抽样 |
| 音频 | AAC / AC3 / EAC3 / DTS / TrueHD / FLAC / Opus（含 passthrough） |
| 字幕 | SRT / ASS（libass）/ PGS / VobSub / 内嵌 / 在线 |
| 交互 | 起播时延、拖动、倍速、音轨切换、PiP、AirPlay、外接屏 |

每格都要记录：能否硬解、起播时延、掉帧、功耗、色偏。**这张表跑完才叫 95%。**
