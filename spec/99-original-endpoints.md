# 99 · 原 App 完整端点提取（原始证据）

从 Rex 1.0.2 主二进制字符串表提取的 63 条路径。其中 license / points / security / attestation 四组在 NetCove 中已按要求移除，此处保留原始清单作为证据与未来扩展参考。

## 已移除（付费墙 / 设备证明 / 积分）

- `/api/device/attestation/`
- `/api/license/dino/bind`
- `/api/license/dino/get`
- `/api/license/drivemby/provision`
- `/api/license/playback/`
- `/api/license/playback/challenge`
- `/api/license/playback/claim`
- `/api/license/playback/lease`
- `/api/license/playback/report`
- `/api/license/points/`
- `/api/license/points/balance`
- `/api/license/points/beat`
- `/api/license/points/initialize`
- `/api/license/points/redeem`
- `/api/license/points/redemptions`
- `/api/license/points/session`
- `/api/license/points/settle`
- `/api/license/points/shop`
- `/api/license/points/transactions`
- `/api/license/points/use`
- `/api/license/status`
- `/api/license/storekit/activate`
- `/api/license/telegram/group/invite`
- `/api/license/telegram/group/status`
- `/api/security/v1/`
- `/api/security/v1/challenge`
- `/api/security/v1/enrollment/admission`
- `/api/security/v1/migration/challenge`
- `/api/security/v1/migration/complete`
- `/api/security/v1/operation/recover`
- `/api/security/v1/operation/recover/challenge`
- `/api/security/v1/policy`
- `/api/security/v1/register`
- `/api/security/v1/register/recover`
- `/api/security/v1/revoke/complete`
- `/partner/v1/grant/redeem`

## 已进入 NetCove 契约（详见 spec/02-openapi.yaml）

- `/api/access/renew`
- `/api/access/sign-in`
- `/api/catalog/match`
- `/api/catalog/title-hints`
- `/api/discovery/ai-search/`
- `/api/integrations/`
- `/api/metadata/playback/metadata`
- `/api/modules/acceleration/`
- `/api/notifications/`
- `/api/support/attachments/signature`
- `/api/support/feedback`
- `/api/widgets/key-session`
- `/v1/chat/completions`
- `/v1/native/account/delete`
- `/v1/native/account/delete/code`
- `/v1/native/email/bind`
- `/v1/native/email/change/code`
- `/v1/native/email/change/verify`
- `/v1/native/email/code`
- `/v1/native/email/login`
- `/v1/native/email/verify`
- `/v1/native/passkeys/add/options`
- `/v1/native/passkeys/add/verify`
- `/v1/native/passkeys/list`
- `/v1/native/passkeys/remove`
- `/v1/native/session/logout`
- `/v1/native/token/refresh`
