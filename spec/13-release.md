# 13 · 发布收尾：签名密钥 / 隐私清单 / CI

## 13.1 模块签名密钥流程（已打通并验证）

```bash
python3 tools/pack_module.py --genkey Config/dev-signing          # 1) 生成 Ed25519 密钥对
python3 tools/pack_module.py examples/modules/hello-netcove \
        --sign Config/dev-signing/module-signing.key \
        -o examples/dist/tv.netcove.example.hello-1.0.0.rexmod    # 2) 签名打包
python3 tools/verify_module.py examples/dist/…rexmod              # 3) 独立校验
```

客户端信任的公钥写在 `Config/Info.plist` 的 **`NetCoveModuleKey`**（Ed25519 raw，base64）。
本次已写入开发密钥对的公钥：

```
40xjdPGlxpyVTYx+n5mzLk+X7XwrKSXS8i2MnDCHT6g=
```

> ⚠️ **`Config/dev-signing/` 里是开发密钥**，只用于本地联调。正式发布前请重新生成密钥对、
> 把新公钥写进 Info.plist，并且**不要把私钥放进仓库或分发包**（`.gitignore` 已排除 `*.key`）。

### 摘要与签名的自指问题（已修）

第一版实现有个坑：先算 digest → 把签名写进 `module.json` → 再算一遍 digest，导致
客户端验签时用的 digest 和签名覆盖的 digest 不一致，永远验不过。

现在的规则（Python 与 Swift 逐字节一致）：

```
digest = SHA256(
  "module.json" + \0 + canonical(manifest 去掉 signature) + \0
  + for each other file (sorted): path + \0 + content + \0
)
canonical(manifest) = json.dumps(去掉 signature, sort_keys=True, separators=(',',':'), ensure_ascii=False)
```

- `signature` 不参与摘要 → 签名前后 digest 相同（packer 里有断言，Swift 有单测）
- 客户端手写规范化序列化（不用 `JSONEncoder`，避免转义差异），键序固定为
  `author / capabilities / entry / id / name / version`
- 打包工具会**拒绝清单里的未知字段**，防止两端规范化结果不一致

验证记录：

```console
$ python3 tools/verify_module.py examples/dist/tv.netcove.example.hello-1.0.0.rexmod
digest  : 0fc4272f55ef603630665cb8d34aa272343a435a1e1244ec1d58b384a3d0426a
signature: valid
OK: package valid
```

## 13.2 隐私清单（PrivacyInfo.xcprivacy）

| 项 | 值 |
|---|---|
| `NSPrivacyTracking` | `false` |
| `NSPrivacyTrackingDomains` | 空 |
| `NSPrivacyCollectedDataTypes` | 空（App 不上报用户数据；账号只用于用户自己的同步） |
| `NSPrivacyAccessedAPITypes` | `UserDefaults`（CA92.1）、`FileTimestamp`（C617.1） |

只声明真正用到的两个类别：设置/进度存 UserDefaults；扫描库时读文件修改时间。
没有读取磁盘空间、没有系统启动时间、没有广告标识符。

## 13.3 授权与导出

`Config/NetCove.entitlements`：iCloud 容器 `iCloud.tv.netcove.app`、CloudKit 服务、
App Group `group.tv.netcove.app`、`aps-environment`（Development，发布时改 Production）。

`Config/ExportOptions.plist`：`method=development`、自动签名、剥离 Swift 符号、上传 dSYM。

## 13.4 构建脚本

```bash
scripts/ci.sh                    # 静态自检 → 模块校验 → 矩阵一致性 → xcodegen → xcodebuild test
scripts/release.sh <TEAM_ID>     # 归档 + 导出 ipa → build/export/
```

`ci.sh` 的五步里前三步是纯脚本，**在这台机器上就能跑**（已跑通），后两步需要 macOS + Xcode。

## 13.5 单元测试（`Tests/NetCoveTests/`，6 个文件）

| 文件 | 覆盖 |
|---|---|
| `ScrapePipelineTests` | 电影/剧集/中文剧集文件名解析、置信度排序 |
| `SubtitleParserTests` | SRT 解析、时间戳、格式判定 |
| `DanmakuParserTests` | B 站 XML 解析（含实体）、轨道分配不重叠 |
| `EngineRouterTests` | MP4→AVPlayer、MKV→FFmpeg、DV P5→FFmpeg、DV P8→系统、120fps→FFmpeg |
| `RexModPackageTests` | 规范化清单与 Python 逐字节一致、digest 与 Python 一致、签名不影响 digest |
| `AppConfigTests` | 包身份、端点方法/域名、17 个端点路径、无付费墙上限 |

`RexModPackageTests` 里的两个期望值是**用 Python 算出来再写死的**，所以它实际是跨语言一致性测试。

## 13.6 静态自检（`tools/verify.py`，现共 14 项）

新增：隐私清单键、授权文件键、导出配置、图标完整性（12 项含 1024）、启动画面资源、
Info.plist 关键键、测试文件数、CI 脚本可执行位。
