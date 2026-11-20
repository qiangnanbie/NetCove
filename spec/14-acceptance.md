# 14 · 验收清单（可执行）

这份文件取代"我觉得差不多了"：每一项都给出命令与预期结果。
带 🖥 的在这台机器上就能跑；带 📱 的需要 Mac + 真机（我无法代跑）。

## 14.1 静态自检（🖥 已通过）

```console
$ python3 tools/verify.py
OK: all checks passed
```

14 项：Swift 括号配平、`project.yml` 路径、客户端端点 ⊆ OpenAPI、中英键集一致、
付费墙残留为零、必交付文件、着色器 entry、i18n 覆盖率、调参矩阵行数、调参产物、
示例模块与打包产物、隐私清单、授权/导出配置、图标与启动画面、Info.plist 关键键、
测试文件数、CI 脚本可执行位。

## 14.2 一致性审计（🖥 已通过）

```console
$ python3 tools/audit.py
== notes ==
  - Endpoint.path: 17/17 cases covered
  - Endpoint.method: 17/17 cases covered (default 覆盖)
  - Endpoint.isAuthDomain: 17/17 cases covered (default 覆盖)
  - 类型引用: 194 个自有类型全部有定义
  - 导航目的地: 17 个 View 定义全部可解析
  - 文档数字: 矩阵 149 行 / 测试 6 文件 / 源码 54 文件
== warnings ==
  ! (none)
== errors ==
  ✗ (none)
OK: audit passed
```

审计能抓的**编译级错误**：`Endpoint` 三处 switch 漏 case（Swift 会直接编译失败）、
引用未定义的自有类型、`NavigationLink` 指向不存在的 View、文档数字与实际不符、定义但从未使用的类型。

## 14.3 模块包与签名（🖥 已通过）

```console
$ python3 tools/pack_module.py examples/modules/hello-netcove \
      --sign Config/dev-signing/module-signing.key \
      -o examples/dist/tv.netcove.example.hello-1.0.0.rexmod
$ python3 tools/verify_module.py examples/dist/tv.netcove.example.hello-1.0.0.rexmod
signature: valid
OK: package valid
```

## 14.4 后端（🖥 已通过）

```console
$ cd Server && python3 netcove_server.py &
$ curl localhost:8787/health                       # {"status": "ok", ...}
$ curl "localhost:8787/api/metadata/search?q=inter" # Interstellar 命中
$ curl -X POST localhost:8787/v1/native/email/code -d '{"email":"a@b.com"}'
$ curl -X POST localhost:8787/v1/native/email/login -d '{"email":"a@b.com","code":"<debug_code>"}'
```

19 条路由覆盖客户端全部 17 个端点（`tools/verify.py` 会核对这项）。

## 14.5 编译与单测（📱 需要 Mac）

```console
$ brew install xcodegen && xcodegen generate
$ xcodebuild test -project NetCove.xcodeproj -scheme NetCove \
      -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

预期：6 个测试文件全部通过。其中 `RexModPackageTests` 的两个期望值是用 Python 算出来写死的，
所以它能证明 Swift 与 Python 的签名摘要逐字节一致。

## 14.6 真机验收（📱 需要设备）

| 项 | 怎么做 | 通过标准 |
|---|---|---|
| 起播 | 跑 `spec/tuning/matrix.csv` 全部用例 | P95 ≤ 1500 ms |
| 掉帧 | 同上，看 `dropped_frames` | ≤ 1% |
| 硬解 | 同上，看 `hardware_decode` | 1080p 及以下 100% 硬解 |
| 功耗 | Xcode Energy / `powermetrics` | ≤ 3500 mW |
| DV P5 | 播 Profile 5 样片，对着色卡 | 无偏紫/偏灰，肤色正确 |
| DV P8 | 播 Profile 8.1/8.4 | 可降级到 HDR10 正常显示 |
| HDR10 | 播 HDR10 样片 | 高光不过曝、暗部有细节 |
| 120fps | 播 120fps 样片 | 走 FFmpeg 路径且不掉帧 |
| 字幕 | SRT/ASS/VTT/PGS/VobSub 各一条 | 样式与时间轴正确 |
| AI 字幕 | 播放无字幕片源，切「Auto (AI)」 | 本机生成并跟随时轴 |
| 弹幕 | 载入 B 站 XML | 8 轨不重叠，200 条不掉帧 |
| 投屏 | 局域网内 DLNA 电视 | 能发现并起播、暂停 |
| 环境锁 | 设 PIN → 切环境 → 冷启动 | 每次都要求解锁；5 次错误锁 5 分钟 |
| 同步 | 两台设备登录同账号 | 库/进度 5 分钟内收敛 |
| 模块 | 安装示例 `.rexmod` → Probe | `onDiscover` 返回条目，日志可见 |

## 14.7 上线前必须替换

1. `Config/dev-signing/` 换成生产 Ed25519 密钥对，并更新 Info.plist 的 `NetCoveModuleKey`
2. `Config/NetCove.entitlements` 的 `icloud-container-environment` → `Production`、`aps-environment` → `production`
3. `Config/ExportOptions.plist` 的 `method` 按渠道（app-store / ad-hoc）调整
4. `AppConfig` 里三个域名换成你的真实域，并做证书固定

## 14.8 当前诚实结论

| 层 | 状态 |
|---|---|
| 代码与文档一致性 | ✅ 机器可验证，全绿 |
| 结构完整性（能编译的程度） | ✅ 静态层面无疑问；**未经真实编译验证**（无 macOS/Xcode） |
| 服务端 | ✅ 本机可跑，端点全覆盖 |
| 播放/画质/同步的真实表现 | ❌ 未验证，需要真机 |
| 品牌与法务 | ⚠️ 名称/图标为原创，但上架前请自行确认不与现有商标冲突 |
