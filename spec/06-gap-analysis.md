# 06 · 差距清单：从骨架到 95%（第九轮更新）

当前仓库给的是**可编译的骨架 + 可信的规格**。要变成能用的 NetCove，按下面顺序补，权重是它对"像不像"的贡献。

## 第九轮新增（搜索 / 片单）

- [x] **搜索**：本地库过滤 + 远端元数据搜索，300ms 防抖，后端不可用时回落 TMDB 直连
- [x] **片单**：`WatchlistStore` 持久化，详情页「Add to List」真正写入并可反选，观看页入口可管理
- [x] 审计与自检复跑全绿

## 第八轮新增（一致性审计 + 接线补齐）

- [x] **新增审计工具** `tools/audit.py`：端点 switch 覆盖、类型引用、导航目的地、文档数字、死代码
- [x] **审计零告警**：清掉 2 个被替代的死代码（`ScriptModuleEngine` / `ScriptModuleRepository`）、
  `ScriptModuleManifest` 别名、`SubtitleTrack`、`SubtitleError`
- [x] **AI 字幕真正接线**：播放器切「Auto (AI)」→ 本机识别 → 按时轴显示（此前只是有服务没入口）
- [x] **DV 检测真正接线**：`DolbyVisionDetector` 现在参与帧描述构造，决定 `transfer` 与 uniform
- [x] **验收清单** `spec/14-acceptance.md`：每项都有命令与通过标准，明确区分"本机可验"与"需真机"

## 第七轮新增（发布收尾）

- [x] **签名链路打通**：Ed25519 密钥生成 → 签名打包 → 客户端规范化验签；
  修掉了「摘要自指」这个必然导致验签失败的 bug（签名前后 digest 必须相同）
- [x] **跨语言一致性**：Python 与 Swift 的 canonical manifest 逐字节对齐，且有单测锁死
- [x] **隐私清单** `PrivacyInfo.xcprivacy`：不上报数据、两个 API 类别（UserDefaults / FileTimestamp）
- [x] **授权与导出**：entitlements（iCloud 容器 + App Group + APNs）、ExportOptions
- [x] **启动画面**：LaunchMark + LaunchBackground 资源与 Info.plist 接线
- [x] **单元测试**：6 个测试文件（刮削/字幕/弹幕/引擎分流/模块摘要/配置）
- [x] **构建脚本**：`scripts/ci.sh`（前三步纯脚本可跑）、`scripts/release.sh`
- [x] **自检扩到 14 项**：隐私清单、授权、图标、启动画面、测试、脚本可执行位

## 第六轮新增（脚本模块 / AI 字幕模型管理）

- [x] **`.rexmod` 包格式**：zip 容器 + 清单 + 摘要 + 可选 Ed25519 签名，客户端只解 stored 条目
- [x] **打包工具** `tools/pack_module.py`：打包 / 签名 / 生成密钥，示例模块已打包并核对结构
- [x] **JS 双向桥**：`netcove.fetch` 返回 Promise（Swift async 回调）、`log`、命名空间 `storage`
- [x] **模块调试面板**：装载、Probe、卸载、沙箱参数可视化、实时日志、文件导入
- [x] **AI 字幕模型管理**：内置 FunASR-nano / Qwen3-ASR 目录、逐文件下载带进度、可选 SHA-256 校验、安装/删除
- [x] **接线**：`SherpaOnnxBridge` 优先用指定模型目录；设置页新增 AI 字幕与模块入口

## 第五轮新增（零拷贝 / 调参自动化 / 多语言收尾）

- [x] **零拷贝渲染**：`VideoToolboxDecoder`（硬解 + avcC/hvcC 解析）+ `CVMetalTextureCache` 直出纹理，软解自动回落
- [x] **调参流水线**：`tools/tuning_matrix.py` 生成 149 条用例矩阵 + 结果回填成 `EngineTuning.generated.swift`，已跑通示例链路
- [x] **客户端开关**：设置里可切换实测调参与默认参数，并显示 `tuningSummary`
- [x] **多语言收尾**：13 语言全部 71 键，除同形词外均已翻译（zh-Hans 100%）
- [x] **自检扩展**：矩阵行数与生成产物纳入 `tools/verify.py`（现共十项）

## 第四轮新增（渲染 / 云盘 / 多语言）

- [x] **DV P5 色彩链路**：`DolbyVisionP5.msl` 全链（YUV→LMS'→PQ 线性→BT.2020→BT.2390/BT.709），level5 裁剪
- [x] **Metal 视频渲染器**：逐平面纹理上传、DV/SDR 双管线、`MetalVideoView`，且引擎已暴露 surface
- [x] **解码/渲染解耦**：`VideoFrameDescriptor` 让渲染层不依赖 Libav*
- [x] **弹幕 Metal 渲染**：CoreText 图集 + instanced quads，一次 draw call，替代 SwiftUI 层（保留回退）
- [x] **云盘**：`CloudDriveProvider` 统一接口；115 设备码+列目录+直链已实现，光雅走 WebDAV，UGREEN 骨架
- [x] **多语言**：13 个 lproj × 71 键，键集强制一致（zh-Hans 100%、ja/ko/zh-Hant/HK ~97%、de/fr/es ~70%、其余 ~31% 英文回退）
- [x] **自检扩展**：着色器存在性与 entry point、本地化覆盖率纳入 `tools/verify.py`

## 第三轮新增（同步 / 环境锁 / 弹幕 / 投屏 / 自检）

- [x] **CloudKit 同步**：`netcove-main` zone、五类实体映射、增量拉取、`modifiedAt` 冲突合并、周期调度
- [x] **环境锁**：6 位 PIN（加盐 12k 轮迭代 + 常量时间比较）、5 次失败冷却、Face ID、四档自动锁、全屏门禁
- [x] **弹幕**：B 站 XML / JSON 解析、8 轨调度、SwiftUI 渲染层
- [x] **投屏**：DLNA/UPnP（SSDP + AVTransport SOAP）、AirPlay 系统路由、Chromecast 占位
- [x] **本地化**：en + zh-Hans 各 71 键，键集一致性纳入自检
- [x] **静态自检**：`tools/verify.py` 七项检查全绿，服务端 17/17 覆盖
- [x] **契约收敛**：OpenAPI 重写为无付费墙 17 端点；原 62 条存证 `spec/99-original-endpoints.md`

## 第二轮新增（无付费墙 + 内核/扫描/后端/UI）

- [x] **移除全部付费墙**：license/points/attestation/lease 删除，`FeatureAccess` 全开，设置页无购买入口
- [x] **后端参考实现**：`Server/netcove_server.py`（零依赖，本机跑通，见 `08-server.md`）
- [x] **播放内核**：`EngineRouter` 双引擎分流、AVPlayer 实现、FFmpeg 实现（`#if canImport` 自动启用）、播放时钟、DV 识别与 P5/P7/P8 决策
- [x] **字幕管线**：SRT/VTT 解析、ASS/PGS 路由、样式模型
- [x] **AI 字幕**：音频抽取 + Speech.framework 路线 + sherpa-onnx 接口
- [x] **扫描**：Jellyfin/Emby、Plex、WebDAV/DAVS、SMB（AMSMB2 可选）、本地目录、STRM
- [x] **刮削**：文件名解析（SxxExx/年份/分辨率/噪声词过滤）+ 服务端匹配 + TMDB 直连回落
- [x] **UI**：发现页模块系统、详情页、播放器、媒体库新增/扫描/删除、环境管理、观看记录、设置
- [x] **脚本模块**：沙箱白名单、限流、审计日志、模块安装与清单校验

## 第一轮已完成

- [x] 全量后端契约（62 个端点，OpenAPI 3.1）
- [x] 模块边界与 1199 个类型清单（26 个一方模块）
- [x] 授权 / 额度 / 积分链路时序（可照抄实现）
- [x] 云同步数据模型（26 record type / 538 字段）
- [x] 设计系统 token（色彩/圆角/间距/字号/海报比例）
- [x] 可编译工程骨架：入口、四入口壳、网络层、会话、钥匙串、授权门禁、设备证明、播放会话、脚本引擎
- [x] 原创图标、Info.plist（bundle `tv.netcove.app`、`netcove://`、Bonjour 改名）

## 待补（按权重大小）

### 1. 播放内核 25%
- [ ] 接入 FFmpeg（自编 Libav*）+ libplacebo 渲染路径
- [ ] AVPlayer 路径走 KSPlayer 外壳，接 AirPlay/PiP/外接屏
- [ ] DV P5/P8、HDR10、120fps 分流与 tone mapping
- [ ] 跑完 `04-playback-tuning.md` 的验收矩阵，参数落到 `EnginePreferences`

### 2. 服务端 20%
- [ ] 按 `02-openapi.yaml` 实现 api / auth / feedback 三个域
- [ ] App Attest 校验（证书链 + nonce + 重放窗口）
- [ ] lease/report 的配额结算与幂等
- [ ] 积分账本（session/beat/settle/use）与抽奖

### 3. 媒体库与扫描 15%
- [ ] Jellyfin/Emby/Plex 客户端、SMB2（AMSMB2）、WebDAV、115/绿联/光雅云盘
- [ ] 刮削匹配流水线（文件名解析 → 标题提示 → 目录匹配）
- [ ] WCDB 持久化 + CloudKit 双向同步（按 `07-cloudkit.md`）

### 4. 界面重建 20%
- [ ] 发现页模块系统（内置页 + 自定义模块 + 编辑态）
- [ ] 详情页（季集、演职员、相似推荐、预告）
- [ ] 播放器 UI（控制层、手势、字幕样式、弹幕）
- [ ] 观看环境管理（创建/复制/合并/迁移、PIN、Face ID、自动锁）
- [ ] 设置全量页（播放/字幕/环境/反馈/关于）+ 14 语言本地化

### 5. AI 字幕与语音 10%（接口已就绪，需模型）
- [ ] onnxruntime + sherpa-onnx（FunASR-nano / qwen3-asr 权重公开，运行期下载）
- [ ] 语音识别 → 字幕时间轴对齐、翻译（可选走第三方 LLM 端点）

### 6. 脚本模块体系 10%（沙箱/限流/安装已就绪，JS 异步桥待补）
- [ ] CommonJS 执行沙箱 + 宿主桥（HTTP/TMDB/播放/弹幕）
- [ ] 模块清单签名与分发格式
- [ ] 调试日志面板（原 App 有 `RexScriptDebugLogStore`）

## 到 95% 的现实路径

| 阶段 | 产出 | 人月（单人） |
|---|---|---|
| M1 | 骨架跑通 + 单库本地播放（MP4/H.264） | 1.5 |
| M2 | 三家媒体服务器 + SMB/WebDAV + 元数据 | 2 |
| M3 | FFmpeg 路径 + DV/HDR + 字幕全格式 | 2.5 |
| M4 | 服务端 + 授权 + 积分 + 同步 | 2 |
| M5 | 界面全量 + 14 语言 + 环境管理 | 2 |
| M6 | AI 字幕 + 脚本模块 + 调参验收 | 1.5 |

合计约 **11.5 人月**；3 人并行约 **4 个月**。这不是估算的乐观值——权重大的两项（播放内核、服务端）都是"必须自己在真机上磨"的活。

## 尚缺（决定最后 5%）

| 项 | 说明 | 权重 |
|---|---|---|
| DV P5 真机校色 | 着色器写完，IPTPQc2 矩阵与 RPU 字段仍需真机比色卡校准 | 高 |
| 真实调参数据 | 流水线就绪，但 matrix.csv 需要在真机上跑出真实数字 | 高 |
| Chromecast | 需 google-cast-sdk 与 app id | 低 |
| 正式签名密钥 | 已内置开发公钥；上线前需换生产密钥对（私钥不入库） | 中 |
| ASR 模型托管 | 目录已内置，需你把模型放到自己的 `assets` 域 | 中 |
| UGREEN 云盘 | 需 NAS 开放平台接口 | 中 |
| Chromecast | 需 google-cast-sdk + app id | 低 |
| 云盘（115/UGREEN/Guangya） | 需各自开放平台授权 | 中 |
| 真机验收矩阵 | `04-playback-tuning.md` 那张表必须跑完并回填参数 | 高 |

## 边界

- 原 App 的品牌素材（图标、名称、Dino 形象、4832 条文案原文）未复制：图标是重绘，文案是空实现待自写。要"像素级一样"就必须自己重绘/重写，否则是侵权，上架必下架。
- 原 App 的服务端与调参先验不在这份交付里，也不可能从包里拿到。
