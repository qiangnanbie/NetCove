# CHANGELOG

按轮次记录，便于回溯每一步加了什么。

## R1 · 拆解与骨架
- 从 IPA 提取：包身份、MH_MACH 结构、110 条 dylib、26 个一方模块、1199 个类型
- 发现注入的 `hwpatch.dylib`（伪造 iCloud/App Group entitlement）
- 产出：62 端点 OpenAPI、CloudKit 26 record type、可编译工程骨架、原创图标

## R2 · 去付费墙 + 内核 + 后端 + UI
- 移除 license/points/attestation/lease，`FeatureAccess` 全开
- 双引擎路由、AVPlayer 实现、FFmpeg 实现、播放时钟、DV 决策
- 6 个扫描 provider、刮削流水线、元数据服务、观看记录
- 参考后端（零依赖）+ 发现页模块系统、详情、播放器、库管理、环境管理、设置

## R3 · 同步 / 锁 / 弹幕 / 投屏 / 自检
- CloudKit 增量同步（`CKFetchRecordZoneChangesOperation`）+ 冲突合并
- 环境锁（加盐 12k 轮迭代 PIN + Face ID + 四档自动锁 + 全屏门禁）
- 弹幕解析与调度、DLNA/AirPlay 投屏
- `tools/verify.py` 七项自检

## R4 · 渲染 / 云盘 / 多语言
- DV P5 全链着色器（IPTPQc2 → BT.2020 → BT.2390/BT.709）+ level5 裁剪
- Metal 视频渲染器、`VideoFrameDescriptor` 解耦、弹幕 Metal 批渲染
- 云盘 provider（115 实现 / 光雅 WebDAV / UGREEN 骨架）
- 13 语言 lproj，键集强制一致

## R5 · 零拷贝 / 调参自动化
- `VideoToolboxDecoder`（avcC/hvcC 解析）+ `CVMetalTextureCache` 零拷贝
- `tuning_matrix.py`：149 条验收矩阵 + 结果回填成 `EngineTuning.generated.swift`
- 客户端开关 Use measured tuning；多语言补齐

## R6 · 模块体系 / AI 字幕
- `.rexmod` 包格式（zip + 清单 + 摘要 + Ed25519 签名）
- `pack_module.py` 打包/签名/生成密钥、示例模块、客户端解包器
- JS Promise 双向桥、宿主桥白名单限流、调试面板
- ASR 模型管理（下载/校验/删除）

## R7 · 发布收尾
- 修「摘要自指」bug：签名不参与摘要，两端 canonical manifest 逐字节一致
- `PrivacyInfo.xcprivacy`、entitlements、ExportOptions、启动画面
- 6 个 XCTest、`ci.sh` / `release.sh`、自检扩到 14 项

## R8 · 一致性审计
- `tools/audit.py`：端点 switch 覆盖、类型引用、导航目的地、文档数字、死代码
- 修 4 处：AI 字幕接线、DV 检测接线、删 2 个被替代的死代码类型
- `spec/14-acceptance.md` 可执行验收清单
