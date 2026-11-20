# NetCove 状态卡（一页看完）

包标识 `tv.netcove.app` · iOS 17+ · Swift 5.9 / SwiftUI · **无付费墙**
63 个 Swift 文件 / 7.7k 行 · 13 语言 × 71 键 · 222 个交付文件

---

## ① 我做完了什么

| 能力 | 实现 |
|---|---|
| 播放内核 | 双引擎路由（AVPlayer / FFmpeg）、VideoToolbox 硬解 + 零拷贝、软件解码回落、播放时钟、seek |
| 画质 | Dolby Vision P5 全链着色器（IPTPQc2→BT.2020→BT.2390/BT.709）、DV P8/HLG/HDR10 分流、4K/120fps |
| 字幕 | SRT/ASS/VTT/PGS/VobSub 路由、样式模型、本机 AI 字幕（音频抽取 + Speech + sherpa 接口） |
| 弹幕 | B 站 XML/JSON 解析、8 轨防重叠调度、Metal instanced 渲染（SwiftUI 版保留回退） |
| 媒体库 | Jellyfin/Emby、Plex、WebDAV(S)、SMB2、115/光雅/UGREEN、本地目录、STRM + 刮削 + TMDB 回落 |
| 多端 | CloudKit 增量同步（冲突按 modifiedAt 合并）、设备间 Bonjour 库同步入口 |
| 隐私 | 观看环境隔离 + PIN（加盐迭代）+ Face ID + 四档自动锁 + 全屏门禁 |
| 投屏 | DLNA（SSDP + AVTransport）、AirPlay 系统路由 |
| 扩展 | `.rexmod` 包（zip + 摘要 + Ed25519 签名）、JS Promise 双向桥、沙箱限流、调试面板 |
| 界面 | 发现页模块系统、搜索、详情、播放器、片单、观看记录、库管理、环境管理、设置 |
| 后端 | 零依赖参考实现，19 路由覆盖客户端全部 17 端点 |
| 依赖栈 | 与 Rex 同款：KSPlayer/Alamofire/Nuke/AMSMB2/WCDB（SPM）+ FFmpeg/libplacebo/libass/libdovi/sherpa-onnx/GoogleCast（自编/CocoaPods） |
| 持久化 | WCDB 实现已就绪（链接后自动启用），否则回落 JSON |
| 本地化 | 14 语言 × 71 键，全部已声明 |

## ② 我能证明什么（证据在 `spec/verification-log.txt`）

```console
$ python3 tools/verify.py     → OK: all checks passed      # 15 项结构检查
$ python3 tools/audit.py      → OK: audit passed          # 6 项一致性审计，零告警
$ python3 tools/verify_module.py …rexmod → signature: valid
$ python3 tools/tuning_matrix.py generate → 149 cases
$ curl localhost:8787/…       → health / search / match / 账号 全部命中
```

审计能抓的是**编译级错误**：端点 switch 漏 case、引用未定义类型、导航指向不存在 View、文档数字不实、死代码。

## ③ 我不能证明什么（这就是缺口）

| 项 | 为什么 |
|---|---|
| 能编译 | 本机是 Android 上的 proot Ubuntu，**没有 macOS / Xcode / swiftc** |
| 能播、画质对 | 没有 iOS 设备，没跑过一帧画面，DV 未校色 |
| 同步、锁、投屏真实行为 | 同上；CloudKit schema 也需在你的容器里部署 |
| 性能数字 | `matrix.csv` 要在真机上跑才有意义 |

**结论**：实现层面我认为到位了，`可用度 95%` 这个判断我给不出——它必须由真机验收来定义。

## ④ 你要做的 5 步

```bash
# 1) Mac 上编译
brew install xcodegen && xcodegen generate && open NetCove.xcodeproj   # 填 Team ID

# 2) 单测
xcodebuild test -project NetCove.xcodeproj -scheme NetCove \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO

# 3) 真机验收（15 组，见 spec/14-acceptance.md）并回填参数
python3 tools/tuning_matrix.py apply spec/tuning/matrix.csv

# 4) 换生产密钥与域名
python3 tools/pack_module.py --genkey keys/     # 新密钥对 → Info.plist NetCoveModuleKey
#   AppConfig 三个域名、entitlements 的 Production、ExportOptions 的 method

# 5) 出包
scripts/release.sh <TEAM_ID>
```

## ⑤ 一句话风险清单

- 首次 Xcode 打开预计有零星编译修正（Metal/CloudKit 的 API 细节最可能）
- DV P5 大概率需要按色卡微调矩阵，否则偏紫/偏灰
- 软解路径是 CPU 上传纹理（硬解才是零拷贝），4K 软解会热
- 名称/图标为原创，但上架前请自行做商标检索
