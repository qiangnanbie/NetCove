# 07 · 云同步规格（CloudKit）

原 App 的私有库 schema 直接以文本形式放在包里（`Rex.ckdb`），这是白送的一份数据模型。

- 容器：`iCloud.<bundle id>`，zone：`rex-main` → NetCove 用 `netcove-main`
- **26 个 record type / 538 个字段**
- 约定：业务时间戳用 `DOUBLE`（epoch 秒），JSON 用 `STRING`，Bool 用 `INT64`
- 权限：无 public create/read，全部 `GRANT WRITE TO "_creator"`

## 26 个 record type

```
catalog                  catalog_activity        drive_subtitle_link
environment              environment_library     environment_script_module
environment_script_source environment_source_toggle episode_cue
home_document            key_alias               later_mark
library_sync_owner       media_preference        media_preference_v
media_watched            playback_progress       resume_candidate
saved_mark               script_module           script_source
settings_sync           skip_segment            trakt_sync_owner
watch_event              watch_tracking
```

## 分组理解

| 组 | record type | 作用 |
|---|---|---|
| 媒体库 | `catalog`、`catalog_activity` | 源定义（serverURL / 凭据 / skipPaths / 扫描策略）+ 活动流水 |
| 观看环境 | `environment`、`environment_library`、`environment_script_*`、`environment_source_toggle`、`home_document` | 环境隔离：每环境一套库/模块/发现页 |
| 观看记录 | `media_watched`、`playback_progress`、`resume_candidate`、`watch_event`、`watch_tracking`、`later_mark`、`saved_mark`、`episode_cue`、`skip_segment` | 进度、追剧、稍后看、跳过片头/片尾片段 |
| 同步治理 | `library_sync_owner`、`trakt_sync_owner`、`settings_sync`、`key_alias` | 多设备谁负责写、Trakt 归属、设置同步、密钥别名 |
| 播放偏好 | `media_preference`、`media_preference_v` | 音轨/字幕/画质选择，带版本号 |
| 脚本 | `script_module`、`script_source`、`drive_subtitle_link` | 第三方模块与云端字幕链接 |

## 迁移注意

1. 先建 schema 再上客户端，字段类型不许漂移（`DOUBLE` 时间戳一旦写成 `TIMESTAMP` 就对不上）；
2. `catalog.credentialsJSON` 是凭据落点，**云端必须加密**（原 App 明文 JSON 字段名，靠容器权限保护）；
3. 多端并发写要有 owner：`library_sync_owner` / `trakt_sync_owner` 就是干这个的。
