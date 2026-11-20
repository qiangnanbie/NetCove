# 09 · 同步 / 环境锁 / 弹幕 / 投屏

第四块工程内容：把"能播"推到"能像产品一样用"。

## 9.1 CloudKit 同步（`Sources/NetCoveData/CloudSyncEngine.swift`）

- Zone：`netcove-main`（原 App 为 `rex-main`），私有库
- 实体映射（先覆盖高频五类，其余按同模式扩展）：

| `SyncEntityKind` | record type | 内容 |
|---|---|---|
| `library` | `catalog` | 媒体源、凭据、跳过路径、扫描策略 |
| `environment` | `environment` | 环境名、默认标记、PIN 开关、自动锁策略 |
| `watchRecord` | `media_watched` | 是否看过、首次/末次时间 |
| `progress` | `playback_progress` | 位置、时长、进度百分比 |
| `settings` | `settings_sync` | 播放/字幕/界面偏好 |

- 三层：`LocalSyncStore`（actor，待推送队列 + change token）→ 推送 `modifyRecords(savePolicy: .changedKeys)` → 拉取
  `CKFetchRecordZoneChangesOperation`（增量 + 删除墓碑）
- 冲突解决：**按 `modifiedAt` 较新者胜**（业务时间戳统一 `DOUBLE` epoch 秒，与 `spec/07-cloudkit.md` 一致）
- 调度：前台 5 分钟周期 + 手动「Sync now」；`isEnabled` 存 UserDefaults

## 9.2 环境锁（`Sources/NetCoveApp/EnvironmentLock.swift`）

| 能力 | 实现 |
|---|---|
| 6 位 PIN | 随机 16 字节盐 + 12,000 轮 SHA-256 迭代，常量时间比较 |
| 失败冷却 | 5 次错误 → 5 分钟锁定（`cooldown` 状态，UI 显示剩余分钟） |
| Face ID / Touch ID | `LAContext.evaluatePolicy`，`.biometrics` 策略，失败回落 PIN |
| 自动锁 | `immediately / 5min / 30min / never` 四档，`markBackgrounded/markForegrounded` 计算 |
| 多环境 | 每个环境独立 PIN（默认 Key 前缀含环境 UUID） |

门禁位置：`RootShell` 在环境切换时判断 `currentLock.state == .locked`，是则全屏 `LockGateView`（自动尝试 Face ID，可输 PIN）。

## 9.3 弹幕（`Sources/NetCovePlayback/Danmaku.swift`）

- 解析：B 站 XML（`<d p="time,mode,size,color,...">`）+ 通用 JSON
- 模式：滚动 / 顶部 / 底部 / 逆向
- 调度：`DanmakuScheduler` 按时间窗吐出弹幕，8 轨防重叠，轨道占用按"约 6 秒穿屏"估算
- 渲染：`DanmakuOverlay`（SwiftUI）。**正式版建议改 Metal/CALayer 批量绘制**，同屏 >200 条时 SwiftUI 会掉帧

## 9.4 投屏（`Sources/NetCovePlayback/CastController.swift`）

| 协议 | 状态 |
|---|---|
| AirPlay | `AVRoutePickerView` 系统面板（`AirPlayRouteButton`） |
| DLNA/UPnP | SSDP `M-SEARCH` 发现 MediaRenderer → 取 `controlURL` → `AVTransport` 的 `SetAVTransportURI` + `Play` + `Pause` |
| Chromecast | 未实现（需 `google-cast-sdk`，且要注册 app id） |

DLNA 实现细节：UDP 组播 239.255.255.250:1900，`poll()` 等 2.5 秒，SOAP 使用
`urn:schemas-upnp-org:service:AVTransport:1`，元数据按 DIDL-Lite 转义。

## 9.5 本地化

| 语言 | 状态 |
|---|---|
| en | 71 键，完整 |
| zh-Hans | 71 键，完整 |
| 其余 12 种 | 待翻译，`tools/verify.py` 会检查键集一致性并在缺失时报错 |

## 9.6 自检

```bash
python3 tools/verify.py
```

检查 7 项：Swift 括号配平（跳过字符串与注释）、`project.yml` 路径存在性、客户端端点 ⊆ OpenAPI、
en/zh 键集一致、付费墙残留为零、必交付文件齐全、后端语法与端点覆盖。当前结果：**全部通过，服务端 17/17 覆盖客户端端点**。
