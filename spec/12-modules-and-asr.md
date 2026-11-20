# 12 · 脚本模块与本地 AI 字幕

原 App 的 `RexScript` 是它最"可扩展"的一块：第三方模块用 JS 写，通过宿主桥出网，
能接管刮削、播放地址解析、弹幕源。NetCove 把这套完整实现了，并把 AI 字幕的模型管理也做成了用户可操作路径。

## 12.1 `.rexmod` 包格式

```
tv.netcove.example.hello-1.0.0.rexmod   ← zip 容器
├── module.json      清单
├── main.js          入口脚本
└── assets/…         可选资源
```

`module.json`：

```json
{
  "id": "tv.netcove.example.hello",
  "name": "Hello NetCove",
  "version": "1.0.0",
  "author": "NetCove",
  "entry": "main.js",
  "capabilities": ["http", "tmdb"],
  "signature": "<hex Ed25519，可选>"
}
```

打包/签名（`tools/pack_module.py`）：

```bash
python3 tools/pack_module.py examples/modules/hello-netcove            # 默认 stored（不压缩）
python3 tools/pack_module.py examples/modules/hello-netcove --sign k.pem
python3 tools/pack_module.py --genkey keys/                            # 生成 Ed25519 密钥对
```

摘要算法（Python 与 Swift 必须一致，已对齐）：

```
for path in sorted(files):
    sha256.update(path + "\0" + content + "\0")
```

签名 = `Ed25519(sign, digest_bytes)`；客户端用内置公钥（Info.plist `NetCoveModuleKey`，base64 raw）
验签。没有内置公钥时，带签名的包**会被拒绝**（防止用户误装上假冒发布者的模块）。

压缩：客户端只解 stored（method 0）条目 —— 模块脚本很小，stored 足够；
遇到 deflate 会返回明确错误而不是静默失败。

## 12.2 运行时与双向桥

`ScriptRuntime`（`Sources/NetCoveScript/ScriptRuntime.swift`）：

| JS 侧 API | 说明 |
|---|---|
| `netcove.fetch(url, {method, headers, body})` | 返回 Promise；Swift 侧异步执行，完成后回调 resolve/reject |
| `netcove.log(...)` | 写入调试日志（`ScriptDebugLogStore`） |
| `netcove.storage.get/set` | 按模块 id 命名空间隔离的 KV（UserDefaults） |

Swift 侧 `call("onDiscover", argument:)` 会自动 await 返回的 Promise —— 用 `then` 注入
`@convention(block)` 回调，配合 `withCheckedThrowingContinuation`。

安全边界：

1. **所有出网走 `ScriptHostBridge`**：域名白名单（模块清单声明 + 用户可见）+ 每分钟请求上限 + 响应体上限；
2. 未声明的域名直接抛 `hostNotAllowed`，并写审计日志；
3. 脚本拿不到 `AVPlayer`、文件系统、钥匙串。

模块可导出 `onDiscover` / `onPlayback` / `onSubtitle`，宿主按需调用（示例见 `examples/modules/hello-netcove/main.js`）。

## 12.3 调试面板

设置 → 模块 → **Script Modules**（`ScriptDebugPanel`）：

- 已装模块列表（名称/版本/能力）、**Load** / **Probe onDiscover** / **Uninstall**
- 运行时状态（idle / loading / ready / failed）
- 沙箱参数可视化（允许域名、限流、响应上限）
- 实时日志（含 JS 异常），一键清空
- 通过文件选择器导入 `.rexmod`

## 12.4 本地 AI 字幕模型管理

`ASRModelManager`（`Sources/NetCovePlayback/ASRModelManager.swift`）：

| 环节 | 实现 |
|---|---|
| 目录 | 内置 FunASR-nano（zh/en，~240 MB）、Qwen3-ASR（zh/en/ja/ko，~420 MB） |
| 下载 | 逐文件 `URLSession.download`，进度按文件数推进，失败即报具体文件名 |
| 校验 | 清单里给了 `sha256` 才对文件做校验（没给就跳过，不假装校验过） |
| 安装位置 | `Application Support/asr-models/<id>/` |
| 识别接入 | `SherpaOnnxBridge.modelDirectory(preferredModelID:)` 优先用指定模型，否则取第一个含 `.onnx` 的目录 |

`remoteBaseURL` 默认指向 `https://assets.netcove.app/asr/<id>/`（自建资产域）——
部署时换成你自己的镜像或模型发布页直链。**模型本体不进 App 包**，避免体积和许可问题。

设置 → AI 字幕 里可直接下载/删除，并显示当前进度与错误。

## 12.5 本轮验证

```console
$ python3 tools/pack_module.py examples/modules/hello-netcove
packed 2 files -> dist/tv.netcove.example.hello-1.0.0.rexmod
  id=tv.netcove.example.hello version=1.0.0 entry=main.js
  sha256=dc823707bec29fcd4f09951d65191750575557112732ede7d37afb0d99044373
  signed=no
```

包内条目与压缩方式已核对：`['main.js', 'module.json'] · method 0 (stored)` —— 与客户端解包器一致。
