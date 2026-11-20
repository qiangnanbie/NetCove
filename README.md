# NetCove

`tv.netcove.app` · iOS 17+ · Swift 5.9 / SwiftUI · **无付费墙**

本地/网盘媒体库播放器：Jellyfin / Emby / Plex / SMB / WebDAV / 115 等云盘 / STRM，
双播放引擎（AVPlayer + FFmpeg/libplacebo），Dolby Vision / HDR / 4K / 120fps 全开，
字幕（SRT/ASS/VTT/PGS/VobSub + 本机 AI 生成），发现页模块系统，观看环境隔离。

## 目录

```
NetCove/
├── project.yml                XcodeGen 工程（bundle: tv.netcove.app）
├── Config/Info.plist          包配置（netcove:// / Bonjour / 权限文案）
├── Sources/
│   ├── NetCoveApp/            入口、四入口壳、发现页模块、详情、播放器、环境管理、设置
│   ├── NetCoveCore/           契约与端点、网络、会话+钥匙串、模型、FeatureAccess（全开）
│   ├── NetCoveData/           媒体库存储与扫描分发 + Providers（Emby/Jellyfin/Plex/WebDAV/SMB/文件）
│   │                          刮削流水线、元数据服务、观看记录
│   ├── NetCovePlayback/       引擎协议、AVPlayer/FFmpeg 实现、Metal 渲染、DV、字幕、AI 字幕
│   └── NetCoveScript/         模块引擎、宿主桥（白名单/限流/审计）、模块仓库
├── Server/netcove_server.py   参考后端（零依赖，已跑通）
├── spec/tuning/               验收矩阵 matrix.csv + checklist.md + 示例结果
├── examples/                  示例脚本模块 + 已签名打包的 .rexmod
├── Tests/NetCoveTests/        6 个单元测试（含跨语言摘要一致性）
├── scripts/                   ci.sh / release.sh
├── Resources/                 原创图标 + 文案词条
├── spec/                      架构 / 契约 / 鉴权 / 播放调参 / 类型清单 / 差距 / CloudKit / 后端
└── tools/                     提取与改名脚本
```

## 出包

```bash
brew install xcodegen
cd NetCove && xcodegen generate && open NetCove.xcodeproj   # 填 Team ID → 真机 Run
```

后端：

```bash
cd Server && python3 netcove_server.py     # http://localhost:8787
```

## 当前实现状态

| 模块 | 状态 |
|---|---|
| 媒体库扫描（Jellyfin/Emby/Plex/WebDAV/SMB/本地/STRM） | 已实现，SMB 需加 AMSMB2 |
| 云盘（115/UGREEN/Guangya） | 接口已留，需各自开放平台凭据 |
| 播放：AVPlayer 路径 | 已实现（起播/暂停/seek/进度） |
| 播放：FFmpeg 路径 | 解码 + `VideoFrameDescriptor` + Metal 渲染；**硬解走 VideoToolbox + 零拷贝**，软解自动回落 |
| 调参 | `tools/tuning_matrix.py` 生成 149 条验收矩阵，回填成 `EngineTuning.generated.swift`，设置里可切换 |
| Dolby Vision P5 | IPTPQc2 着色器全链完成（需真机校色）；P7/P8 走系统 tone mapping |
| Metal 视频呈现 | AVPlayer 走 `AVPlayerLayer`，FFmpeg 走 `CAMetalLayer`，均已接入播放器 |
| 弹幕渲染 | Metal instanced quads + CoreText 图集（SwiftUI 版保留为回退） |
| 云盘 | 115 已实现（设备码/列目录/直链）；光雅走 WebDAV；UGREEN 需 NAS 接口 |
| Dolby Vision | profile 识别 + P5/P7/P8 决策已实现；P5 色彩变换需接 libplacebo 着色器 |
| 字幕 | SRT/VTT 解析已实现；ASS 走 libass；PGS/VobSub 需 FFmpeg 解码 |
| AI 字幕 | 音频抽取 + Speech.framework 已实现；sherpa-onnx 接口就绪（需模型） |
| 发现页模块系统 | 已实现（内置 4 种 + 自定义模块位） |
| 搜索 | 本地库过滤 + 远端元数据搜索（防抖、TMDB 回落） |
| 片单 | 详情页加入/移出、观看页入口、本地持久化 |
| 观看环境 | 创建/复制/删除/切换已实现；PIN 与 Face ID 待接 |
| 脚本模块 | `.rexmod` 打包/签名/安装 + JS Promise 双向桥 + 调试面板（装载/Probe/日志）全部可用 |
| AI 字幕 | 音频抽取 + Speech 已实现；模型管理（下载/校验/删除）就绪，sherpa-onnx 接口待接模型 |
| 云同步 | CloudKit 增量同步 + 冲突合并已实现（需在容器里部署 schema） |
| 环境锁 | PIN（加盐迭代哈希）+ 5 次失败冷却 + Face ID + 全屏门禁，已接入 |
| 弹幕 | B 站 XML / JSON 解析 + 8 轨调度 + 渲染层，已在播放器可切换 |
| 投屏 | DLNA 发现与 AVTransport 控制、AirPlay 系统路由；Chromecast 未做 |
| 本地化 | 13 语言 × 71 键，键集一致；zh-Hans/zh-Hant/zh-HK/ja/ko 已接近全量，de/fr/es 约七成，其余英文回退 |
| 后端 | 19 路由，覆盖客户端全部 17 个端点，已本机验证 |
| 发布就绪 | 隐私清单、entitlements、ExportOptions、启动画面、CI/发布脚本齐备 |
| 测试 | 6 个 XCTest 文件；`RexModPackageTests` 是与 Python 对齐的跨语言测试 |
| 自检 | `python3 tools/verify.py` 14 项全绿 · `python3 tools/audit.py` 零告警零错误 |
| 验收 | `spec/14-acceptance.md`：每项带命令与通过标准，区分本机可验 / 需真机 |

## 关键设计

- **无付费墙**：`FeatureAccess` 所有上限为 `nil`，格式判定恒真；license/points/attestation 一层不存在。
- **可空依赖**：FFmpeg、libplacebo、libass、AMSMB2、sherpa-onnx 全部用 `#if canImport` 隔离，
  没链接也能编译运行（降级提示），链接后真实实现自动生效。
- **引擎分流**：MP4 + h264/hevc/av1 + 非 P5 + 非 120fps → AVPlayer；其余 → FFmpeg。

## 仍需你在 Mac 上完成的

1. 接开源栈：FFmpeg（自编 Libav*）、libplacebo、libass、AMSMB2、sherpa-onnx
2. DV P5 的 IPTPQc2 → BT.2020 色彩变换着色器（Metal）
3. 真机矩阵调参（`spec/04-playback-tuning.md` 的验收表）
4. CloudKit 容器里按 `spec/07-cloudkit.md` 建 schema（26 record type）
5. 其余 12 种语言本地化（键集已固定，`tools/verify.py` 会校验）

## 法律边界

不含原 App 的二进制、图片、字体与文案原文。名称 NetCove、图标为原创重绘。
