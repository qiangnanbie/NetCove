# NetCove 工程交接说明

> 一句话：**代码与规格已完成，机器可验证的部分全绿；剩下 5% 需要 Mac + 真机，我没有那个环境。**

- 包标识：`tv.netcove.app` · 显示名 `NetCove` · iOS 17+ · Swift 5.9 / SwiftUI
- 规模：54 个 Swift 源文件 + 6 个测试文件（约 7.4k 行）· 228 行 Metal 着色器 · 13 语言 × 71 键
- 无付费墙：所有库/环境/格式全开

---

## 1. 五分钟上手

```bash
# ① 静态验证（本机就能跑，无需 Xcode）
python3 tools/verify.py        # 14 项结构检查
python3 tools/audit.py         # 5 项一致性审计（抓编译级错误）

# ② 后端跑起来
cd Server && python3 netcove_server.py     # http://localhost:8787

# ③ 模块包校验
python3 tools/verify_module.py examples/dist/tv.netcove.example.hello-1.0.0.rexmod

# ④ 需要 Mac 才能继续
brew install xcodegen && xcodegen generate && open NetCove.xcodeproj
```

## 2. 目录地图

| 路径 | 内容 |
|---|---|
| `Sources/NetCoveApp/` | 入口、四 Tab 壳、发现页模块、详情、播放器、环境管理、设置、环境锁 |
| `Sources/NetCoveCore/` | 17 个端点的契约、网络层、会话+钥匙串、领域模型、`FeatureAccess`（全开） |
| `Sources/NetCoveData/` | 媒体库存储与扫描分发、6 个源 provider、刮削、元数据、观看记录、CloudKit 同步 |
| `Sources/NetCovePlayback/` | 双引擎路由、AVPlayer / FFmpeg 实现、Metal 渲染、DV、字幕、弹幕、投屏、AI 字幕 |
| `Sources/NetCoveScript/` | `.rexmod` 包解析校验、JS 运行时双向桥、宿主桥、调试面板 |
| `spec/` | 01 架构 · 02 OpenAPI · 03 鉴权 · 04/11 播放与调参 · 05 类型清单 · 06 差距 · 07 CloudKit · 08 后端 · 09 同步锁投屏 · 10 渲染 · 12 模块与 ASR · 13 发布 · 14 验收 · 99 原始端点 |
| `tools/` | verify / audit / pack_module / verify_module / tuning_matrix / i18n / dump_objc / make_icons |
| `Server/` | 零依赖参考后端（19 路由，覆盖客户端全部 17 端点） |
| `Tests/` | 6 个 XCTest 文件，含与 Python 对齐的跨语言摘要测试 |

## 3. 完成度（分层，别混为一谈）

| 层 | 状态 | 证据 |
|---|---|---|
| 架构 / 契约 / 规格 | ✅ 完成 | `spec/` 14 份文档，端点与实现双向对齐 |
| 代码结构与互相引用 | ✅ 静态无疑问 | `audit.py` 零告警：194 类型全有定义、switch 全覆盖 |
| 后端 | ✅ 可运行 | 本机 curl 全部端点通过 |
| 模块打包与签名 | ✅ 可运行 | `signature: valid`，跨语言摘要一致 |
| iOS 编译 | ⚠️ **未验证** | 本机无 macOS/Xcode/swiftc |
| 播放画质 / 同步 / 锁 | ❌ **未验证** | 需真机；`spec/14-acceptance.md` 有 15 组待跑项 |

## 4. 上线前必须替换的 5 处

1. `Config/dev-signing/` → 生产 Ed25519 密钥对（**私钥不入库、不进包**），并更新 Info.plist `NetCoveModuleKey`
2. `Config/NetCove.entitlements` → `icloud-container-environment: Production`、`aps-environment: production`
3. `Config/ExportOptions.plist` → `method` 按渠道调整（app-store / ad-hoc）
4. `Sources/NetCoveCore/AppConfig.swift` → 三个域名换成真实域，并接证书固定
5. `spec/tuning/matrix.csv` 用真机结果回填 → `tuning_matrix.py apply` → 设置里打开 Use measured tuning

## 5. 已知风险（按严重度）

| 风险 | 影响 | 缓解 |
|---|---|---|
| 未真实编译 | 可能有少量 Swift 类型/约束错误 | `audit.py` + 括号配平已覆盖常见类别；首次在 Xcode 打开时预期有零星修正 |
| DV P5 未校色 | 画面可能偏紫/偏灰 | 着色器链路已完整，只需按色卡调矩阵与 RPU 字段 |
| Metal 纹理上传非零拷贝 | FFmpeg 软解路径 CPU 偏高 | 硬解路径已零拷贝；软解仅在回落时使用 |
| 弹幕图集 2048² 上限 | 极端弹幕量可能放不下 | `slot()` 返回 nil 会跳过该条，不会崩 |
| CloudKit schema 未部署 | 同步不可用 | 按 `spec/07-cloudkit.md` 在容器里建 26 个 record type |
| 品牌相似 | 上架风险 | 名称与图标均为原创重绘；仍建议自行做商标检索 |

## 6. 本轮之后的下一步建议

1. 在 Mac 上 `xcodegen generate` + 编译，先修编译错误（预计集中在 Metal/CloudKit 的 API 细节）
2. 跑 `xcodebuild test`，让 6 个测试先绿
3. 按 `spec/14-acceptance.md` 的 📱 表格逐项验收，用 `tuning_matrix.py` 回填参数
4. DV P5 校色：准备 P5 样片 + 色卡，调 `DolbyVisionColorPipeline.uniforms` 的矩阵与 `toneMapMode`
5. 最后替换密钥与域名，出 TestFlight
