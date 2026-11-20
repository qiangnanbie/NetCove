# 依赖栈对齐（与 Rex 同款）

Rex 的 222 MB 里绝大部分是这些库。NetCove 的代码不复制它们，只声明依赖——链接之后包体与内存回到同一量级。

## 可直接用 SPM 接入（已在 `project.yml` 声明）

| 库 | 用途 | 仓库 |
|---|---|---|
| KSPlayer | 系统播放器路线（AVPlayer 壳 + UI） | https://github.com/kingslay/KSPlayer |
| Alamofire | 网络 + 证书固定 | https://github.com/Alamofire/Alamofire |
| Nuke | 图片加载与缓存 | https://github.com/kean/Nuke |
| AMSMB2 | SMB2 客户端 | https://github.com/amosavian/AMSMB2 |
| WCDB.swift | 本地数据库（Rex 同款） | https://github.com/Tencent/wcdb |
| DanmakuKit | 弹幕渲染（备用，主用我们的 Metal 实现） | https://github.com/qyz777/DanmakuKit |

## 需要自行构建（无官方 SPM）

| 库 | 用途 | 做法 |
|---|---|---|
| FFmpeg（Libav*） | 解封装/解码全家桶 | 用 `ffmpeg-kit` 或自编 xcframework；Rex 用的是自编 Libav*.framework 组（Libavcodec 14 MB 等） |
| libplacebo | GPU 渲染 / tone mapping | 需自编 xcframework（Rex 里 17 MB） |
| libass | ASS/SSA 字幕渲染 | 自编 xcframework |
| libdovi | Dolby Vision RPU 处理 | 自编（Rex 里 DoviMatrix 依赖它） |
| sherpa-onnx | 本地语音识别 | https://github.com/k2-fsa/sherpa-onnx 自编 xcframework |
| Google Cast SDK | Chromecast | CocoaPods `google-cast-sdk`（无 SPM） |

## 接入后体积预估（对齐 Rex 实测构成）

| 项 | Rex | NetCove 接入后 |
|---|---|---|
| 主二进制 | 90 MB | ~15–25 MB（代码少、但含 Metal 着色器与 14 语言） |
| FFmpeg + libplacebo + libass + libdovi | ~45 MB | 同量级 |
| 资源（图标/启动画面） | 40 MB（Assets.car） | < 2 MB（矢量/少量 PNG） |
| 语言文案 | 14 语言 × 4,832 条 | 14 语言 × 71 条（按需扩充） |

结论：**Rex 的 40 MB 图片资产 NetCove 不会照搬**，其余部分链接同款库后基本一致。
运行时内存由解码缓冲与纹理决定，不随代码量变化——所以只要 `EnginePreferences` 参数对齐，RAM 就同量级。
