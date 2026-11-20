# 01 · 架构规格

从二进制恢复的一手模块边界：**26 个一方模块 / 1199 个类型**，另有第三方模块（同款开源栈）。

## 一方模块（按类型数量降序）

| 模块 | 类型数 | 职责 |
|---|---:|---|
| `Rex` | 407 | 主 App 壳：路由、环境(Viewing Environment)、设置、分享页、扫描编排、Drivemby 绑定 |
| `RexHome` | 229 | 发现页/首页：推荐位、内置页、编辑态、模块挂载 |
| `RexDetails` | 105 | 影片详情：元数据展示、演职员、季集、相似推荐 |
| `RexPlayerUIKit` | 86 | 播放器 UI：控制层、字幕层、外接屏、画中画 |
| `RexData` | 83 | 本地持久化(WCDB)、记录同步、CloudKit 同步内核 |
| `RexDesign` | 40 | 设计系统：颜色/圆角/间距/图标/徽章 |
| `RexCatalog` | 37 | 目录/索引：分页缓存、刷新绑定、未看提醒 |
| `PreLoadIOContext` | 29 | 播放前 IO 预取与流量控制 |
| `RexPlayerKSPlayer` | 28 | KSPlayer 路线适配 |
| `RexBackend` | 22 | 后端客户端：鉴权、元数据、限额契约 |
| `RexScript` | 21 | 脚本模块引擎：CommonJS 执行、宿主桥、请求合并 |
| `RexHomeCore` | 19 | 首页数据模型与内容 provider |
| `RexPlayerCore` | 16 | 播放调度：引擎选择、预热、缓冲/跳过策略、资源过期 |
| `RexDinoCore` | 12 | 吉祥物与主题（Dino 皮肤） |
| `RexDetailsCore` | 11 | 详情模型与请求聚合 |
| `RexImagery` | 10 | 图片管线：海报、动图、占位 |
| `RexPlayerServices` | 8 | 播放周边服务：AirPlay、字幕下载、弹幕 |
| `ProAVPlayer` | 7 | AVPlayer 增强层（HDR/DV 能力协商） |
| `RexKit` | 6 | 通用工具：日志、并发、字节单位 |
| `DoviMatrix` | 6 | Dolby Vision 元数据矩阵转换 |
| `PoScreenCast` | 5 | 投屏（DLNA/Chromecast 类） |
| `RexBadgeCore` | 4 | 角标/成就渲染 |
| `RexImageryCore` | 3 | 图片缓存与解码底层 |
| `BlurUIKit` | 2 | 模糊/毛玻璃视图 |
| `RexScrape` | 2 | 刮削/匹配流水线 |
| `RexIntegrity` | 1 | 完整性校验与运行环境自检 |

## 第三方模块（同款开源，可直接换用）

| 模块 | 类型数 | 替代方案 |
|---|---:|---|
| `KSPlayer` | 151 | KSPlayer（MIT） |
| `WCDBSwift` | 72 | WCDB / GRDB |
| `Alamofire` | 38 | Alamofire（MIT） |
| `Nuke` | 19 | Nuke 或 Kingfisher |
| `DanmakuKit` | 12 | DanmakuKit |
| `JXPhotoBrowser` | 10 | JXPhotoBrowser 或自研 |
| `SwiftDraw` | 3 | SwiftDraw（SVG） |
| `AEXML` | 3 | AEXML（XML） |
| `KSPlayerSherpa` | 2 | 同款开源库 |

## 分层与依赖规则

```
App 层      NetCoveApp（壳 / 路由 / 四个一级入口）
   │
领域层      NetCoveCore（契约 / 鉴权 / 授权 / 积分 / 设备证明）
   │        NetCoveData（库扫描 / 持久化 / 云同步）
   │        NetCovePlayback（引擎 / 会话 / 门禁）
   │        NetCoveScript（模块引擎）
   ▼
基础设施    网络 · 钥匙串 · 数据库 · 播放内核（AVPlayer/FFmpeg）· 本地 ASR
```

规则（与原 App 一致）：

1. App 层只依赖领域层，不直接碰网络与数据库；
2. 授权判定集中在 `LicenseGate`，播放/加库/建环境三处入口统一调用；
3. 播放会话是唯一能拿到 `lease` 的组件，UI 不得自行请求；
4. 脚本模块只能通过宿主桥出网，禁直连。

完整类型清单见 `spec/types/*.types.txt`（每个模块一个文件）。
