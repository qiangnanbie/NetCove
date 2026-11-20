# 10 · 渲染层：Dolby Vision / Metal / 弹幕

这一层决定"画面对不对、像不像原 App"。原 App 的做法是 FFmpeg 解码 + libplacebo 渲染 + DoviMatrix 处理 RPU；
NetCove 用 **Metal 直接写**，省掉 libplacebo 依赖，也把 P5 的色彩变换暴露成可调参数。

## 10.1 解码与渲染解耦

```
FFmpeg AVFrame ──► VideoFrameDescriptor ──► VideoFrameRenderer (Metal)
   （Libav*）         （与解码器无关）           ├─ DolbyVisionP5.msl
                                                └─ SDRVideo.msl
```

`VideoFrameDescriptor` 只带平面指针、行长、宽高、像素格式、色彩元信息、DV 参数。
这样渲染层**不需要 import Libav\***，没有 FFmpeg 也能编译；`FFmpegPlaybackEngine` 负责把 AVFrame 填进去。

## 10.2 Dolby Vision Profile 5

P5 没有 HDR10 回退层，必须自己走 IPTPQc2：

1. `YUV(BT.2020 非恒定亮度)` × `yuvToLms` → `LMS'`（PQ 域）
2. 每个分量做 **PQ EOTF 反变换**得到线性光
3. 减去 RPU 的 `source_min_pq` 并归一化到 `source_max_pq`
4. `lmsToBt2020` → BT.2020 线性
5. 按目标亮度做映射：SDR 屏用 **BT.2390 EETF** 压到 100 nit，再 `BT.2020 → BT.709`；
   HDR 屏直通 BT.2020
6. level 5 裁剪（RPU 的左右/上下的黑边补偿）

着色器：`Sources/NetCovePlayback/Rendering/Shaders/DolbyVisionP5.msl`（`dvVertex` / `dvFragment`）。

P7/P8 走系统路径（`AVPlayer` 会用回退层做 tone mapping），只有 P5 必须走这条自绘链。

## 10.3 Metal 视频渲染器

`MetalVideoRenderer`（`Rendering/MetalVideoRenderer.swift`）：

| 环节 | 做法 |
|---|---|
| 纹理 | 每平面一张纹理：`r8Unorm`（8bit Y）、`rg8Unorm`（NV12 UV）、`r16Unorm`/`rg16Unorm`（10bit） |
| 上传 | `replace(region:)`，行长直接用解码器给的 `linesize` |
| 管线 | P5 → `DolbyVisionP5`，其余 → `SDRVideo`；片元 uniform 用 `setFragmentBytes` |
| 呈现 | `CAMetalLayer` + `MetalVideoView`（UIViewRepresentable） |

**性能注记（要改的点）**：现在是逐帧 CPU 拷贝。生产应改成
`VideoToolbox 硬解 → CVPixelBuffer → CVMetalTextureCache` 零拷贝，CPU 占用能降一个量级。

## 10.4 弹幕渲染

| 项 | SwiftUI 版（旧） | Metal 版（新） |
|---|---|---|
| 绘制 | 每条一个 `Text` 视图 | 一次 draw call，instanced quads |
| 文字 | 系统排版 | CoreText 画进位图图集（`DanmakuTextAtlas`，2048²） |
| 同屏 200 条 | 掉帧 | 稳（受限于提交的实例数，不受视图树影响） |

流程：`DanmakuScheduler.active(at:)` 出条目 → `DanmakuMetalRenderer.update(items:viewSize:)` 换算 NDC 与 uv →
`draw()`。图集有变化才重新上传。

`Danmaku.metal`：六顶点四边形 + alpha 混合，`discard_fragment` 丢弃透明像素。

## 10.5 云盘接入

`CloudDriveProvider` 协议统一了「鉴权 → 列目录 → 取直链」：

| 平台 | 实现状态 |
|---|---|
| 115 | 已实现：设备码授权（`passportapi/.../authDeviceCode`、`deviceCodeToToken`）、`proapi/ufile/files` 列目录、`ufile/downurl` 取直链 |
| UGREEN | 骨架：需你的 NAS 开放平台地址与 token（接口随固件变动） |
| 光雅 | 已实现：走 WebDAV 兼容层 |

云盘直链通常 **几分钟就过期**，所以播放前必须现取（`playbackURL(fileID:token:)`），不能缓存进库。

## 10.6 本地化覆盖率

| 语言 | 键数 | 已翻译 | 英文回退 |
|---|---:|---:|---:|
| en | 71 | — | 71（基准） |
| zh-Hant / zh-HK | 71 | 70 | 1 |
| ja / ko | 71 | 69 | 2 |
| es / fr / de | 71 | 53 / 50 / 49 | 18 / 21 / 22 |
| ar / it / pt / pt-BR / ru | 71 | 21–22 | 49–50 |

键集由 `tools/verify.py` 强制一致，`tools/i18n.py` 负责补齐（缺失即英文回退，不会出现空文案）。
