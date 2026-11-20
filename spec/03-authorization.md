# 03 · 账号与鉴权（无付费墙版本）

> 原 App 的 license / points / App Attest / playback lease 体系**整体移除**。此文件替代原先的 03-license-flow.md。

## 3.1 设计取舍

| 维度 | 原 App | NetCove |
|---|---|---|
| 付费墙 | 1 库 / 1 环境 / 每天 3 次播放，高阶格式拦截 | **无**：无限库、无限环境、不限次数、4K/DV/HDR/120fps 全开 |
| 设备证明 | DeviceCheck App Attest + 设备密钥 proof | 不需要；本地运行，不上报设备指纹 |
| 播放额度 | challenge → lease → claim → report | 移除；播放只写本地观看记录 |
| 积分经济 | points session/beat/settle/shop/redeem | 移除 |
| 账号 | 邮箱 OTP + passkey，token 才可播 | 可选：不登录也能用全部功能；登录仅用于跨设备同步 |

## 3.2 保留的鉴权

只有一条链路，且是**可选**的（为了云同步/多端）：

```
POST /v1/native/email/code     { email }            → { sent }
POST /v1/native/email/verify   { email, code }      → { verified }
POST /v1/native/email/login    { email, code }      → { access_token, refresh_token, user }
POST /v1/native/token/refresh  (x-netcove-account-token) → 新 token
POST /v1/native/session/logout
GET  /v1/native/passkeys/list
```

Token 是 HS256 JWT，有效期 7 天，放在 `x-netcove-account-token` 头里。

## 3.3 客户端实现（已交付）

- `SessionStore`：token 存 Keychain（`kSecClassGenericPassword`），启动时 `restore()` 并在过期前刷新
- `FeatureAccess`：所有上限为 `nil`（不限），`allowsPlayback()` 恒为 `true`
- 设置页只展示能力清单，没有购买入口

## 3.4 安全提示

去掉付费墙后，唯一还需要保护的是**用户自己的账号**：

1. 邮箱验证码 6 位、10 分钟过期、一次性（服务端删码）；
2. token 不要放进 URL（避免日志泄漏），只走 header；
3. 若接 CloudKit，凭据字段（`credentialsJSON`）在写入前用 `CryptoKit` 对称加密，密钥存 keychain。
