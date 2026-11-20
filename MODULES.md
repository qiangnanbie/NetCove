# 模块边界：Rex 26 个 framework ↔ NetCove 5 个目录

## Rex 的原始划分（从二进制恢复）

| Rex 模块 | 类型数 | 职责 | NetCove 归属 |
|---|---:|---|---|
| `Rex` | 407 | 壳/路由/环境/设置/分享/扫描编排 | `NetCoveApp` |
| `RexHome` | 229 | 发现页、模块挂载、编辑态 | `NetCoveApp`（`HomeModule`/`DiscoverView`） |
| `RexDetails` | 105 | 详情页、季集、相似推荐 | `NetCoveApp`（`DetailsView`） |
| `RexPlayerUIKit` | 86 | 播放器 UI、字幕层、外接屏 | `NetCoveApp`（`PlayerView`） |
| `RexData` | 83 | WCDB、CloudKit 同步 | `NetCoveData` |
| `RexDesign` | 40 | 设计系统 | `NetCoveCore/DesignTokens.swift` |
| `RexCatalog` | 37 | 分页缓存、刷新绑定 | `NetCoveData`（`CatalogService`） |
| `PreLoadIOContext` | 29 | 播放前 IO 预取 | `NetCovePlayback`（`EnginePreferences`） |
| `RexPlayerKSPlayer` | 28 | KSPlayer 适配 | `NetCovePlayback`（`EngineRouter`/`AVPlaybackEngine`） |
| `RexBackend` | 22 | 网络与鉴权契约 | `NetCoveCore` |
| `RexScript` | 21 | 脚本模块引擎 | `NetCoveScript` |
| `RexHomeCore` | 19 | 首页数据模型 | `NetCoveApp` |
| `RexPlayerCore` | 16 | 播放调度/预热/跳过 | `NetCovePlayback` |
| `RexDinoCore` | 12 | 吉祥物与主题 | 未实现（品牌资产不复制） |
| `RexDetailsCore` | 11 | 详情模型 | `NetCoveApp` |
| `RexImagery` | 10 | 图片管线 | `NetCoveCore`（`AsyncImage` 直用） |
| `RexPlayerServices` | 8 | AirPlay/字幕/弹幕 | `NetCovePlayback` |
| `ProAVPlayer` | 7 | AVPlayer 增强/HDR 协商 | `NetCovePlayback` |
| `RexKit` | 6 | 通用工具 | 分散在 `NetCoveCore` |
| `DoviMatrix` | 6 | DV 元数据转换 | `NetCovePlayback/DolbyVision.swift` |
| `PoScreenCast` | 5 | 投屏 | `NetCovePlayback/CastController.swift` |
| `RexBadgeCore` | 4 | 角标/成就 | 未实现（对应付费墙，已移除） |
| `RexImageryCore` | 3 | 图片缓存底层 | 未实现（交给 Nuke） |
| `BlurUIKit` | 2 | 毛玻璃 | 未实现（系统 `.ultraThinMaterial` 足够） |
| `RexScrape` | 2 | 刮削流水线 | `NetCoveData/ScrapePipeline.swift` |
| `RexIntegrity` | 1 | 完整性自检 | 未实现（无付费墙，不需要） |

## 为什么不直接拆成 26 个 target

拆分本身不难，难的是**访问控制**：跨模块的每个类型、每个被引用的成员都得标 `public`。
当前有 **42 个跨模块引用的类型**（清单在 `spec/module-boundaries.md`），盲改必然引入
一批只在编译器里才暴露的错误——而本机**没有 swiftc**，改完无法验证。

所以这一步的正确顺序是：

```bash
# 1) 先拿到边界报告（本机就能跑）
python3 tools/module_map.py --write        # → spec/module-boundaries.md

# 2) 在 Mac 上建 SPM 包，按报告逐个补 public，边补边编译
#    依赖方向（已核验无违规）：
#    Core ← Data ← Playback
#    Core ← Script
#    Core/Data/Playback/Script ← App
```

依赖方向我已用 `tools/module_map.py` 核验：**当前零违规**。
（原本 `NetCoveScript` 反向依赖 `NetCoveApp` 的 `DesignTokens`，已把设计系统下沉到 `NetCoveCore` 修掉。）

## 现在实际的结构

单 target（`NetCove`）+ 5 个目录，目录名与职责对齐 Rex 的模块边界，
`Package.swift` 级的物理拆分留到有编译器的那一步做——那才是能验证的做法。
