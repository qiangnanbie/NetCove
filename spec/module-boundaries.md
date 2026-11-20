# 模块边界（拆分前的 public API 清单）

Rex 的一方模块是 26 个独立 framework；NetCove 目前是单 target 的 5 个目录。
要拆成多模块，下表列出的每个类型及其被引用的成员都必须标记 `public`。

## NetCoveCore → NetCoveApp（11 个类型需 public）

```
APIClient
AppConfig
DesignTokens
FeatureAccess
Library
MediaItem
MediaSourceType
PlayableResource
PlaybackProbe
SessionStore
ViewingEnvironment
```

## NetCoveData → NetCoveApp（7 个类型需 public）

```
CatalogService
CloudSyncEngine
LibraryCredentials
LibraryStore
ScoredMatch
WatchHistoryStore
WatchlistStore
```

## NetCovePlayback → NetCoveApp（14 个类型需 public）

```
AISubtitleService
ASRModelManager
AirPlayRouteButton
CastController
DanmakuComment
DanmakuMetalRenderer
DanmakuMetalView
DanmakuOverlay
DanmakuScheduler
EnginePreferences
EngineRouter
MetalVideoView
PlaybackSession
SubtitleCue
```

## NetCoveScript → NetCoveApp（1 个类型需 public）

```
ScriptDebugPanel
```

## NetCoveCore → NetCoveData（5 个类型需 public）

```
APIClient
Library
MediaItem
MediaSourceType
WatchRecord
```

## NetCoveCore → NetCovePlayback（2 个类型需 public）

```
PlayableResource
PlaybackProbe
```

## NetCoveData → NetCovePlayback（1 个类型需 public）

```
WatchHistoryStore
```

## NetCoveCore → NetCoveScript（1 个类型需 public）

```
DesignTokens
```

## 依赖方向

- `NetCoveCore` → （无）
- `NetCoveData` → `NetCoveCore`
- `NetCovePlayback` → `NetCoveCore`, `NetCoveData`
- `NetCoveScript` → `NetCoveCore`
- `NetCoveApp` → `NetCoveCore`, `NetCoveData`, `NetCovePlayback`, `NetCoveScript`

## 违背依赖方向（必须处理）

- 无（当前引用方向与计划一致）
