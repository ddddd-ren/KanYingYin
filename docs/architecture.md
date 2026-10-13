# 看影音架构边界

## 目标依赖方向

应用启动和全局注册位于 `lib/app/`。业务功能位于 `lib/features/<功能>/`，由用例、领域模型、端口和展示组成；页面目录 `lib/pages/` 逐步退化为路由适配和旧页面兼容层；平台差异位于 `lib/platform/`；跨功能基础能力才保留在 `lib/services/`。

目标方向是：

```text
app -> features -> ports -> adapters -> pages/services
```

其中 `app` 只负责启动和依赖注册，业务流程不应通过 `Modular.get` 隐式串联。

## 已完成的迁移

- `features/library` 已通过 `application/library_ports.dart` 依赖 `LocalLibraryPort`、`CloudLibraryPort` 和 `PlaybackPort`。
- `MediaCategoryModule` 和 `MediaCategoryRuntime` 不再直接导入旧页面控制器；旧控制器由 `app/bindings/library_bindings.dart` 注册为适配器。
- `LocalController` 的索引、目录、TMDB、海报和媒体源流程已移到 `local_library_application_coordinator.dart`，控制器保留 MobX 状态和兼容入口。
- `PlayerController` 的播放生命周期、轨道字幕、Anime4K、播放控制和资源释放流程已移到 `player_playback_application_coordinator.dart`，控制器保留状态外观和兼容入口。
- `services/cloud/core/cloud_core.dart` 收拢公共网盘协议、媒体模型和 range 转播基础设施的导出；夸克、百度、迅雷、OpenList 各自位于独立目录。

## 网盘边界

`cloud/core` 提供凭据、驱动协议、播放传输、远程引用、来源范围和 range 转播的公共入口。`cloud/range` 实现按范围读取、缓存、转播会话和协议。`baidu`、`quark`、`xunlei`、`openlist` 只实现各自 API、认证、解析、驱动和远程读取。

`cloud_provider_registry.dart` 是组合根，负责把来源类型映射到供应商实现；页面只通过注册表、协调器或功能端口使用网盘能力，不应自行判断所有供应商细节。

当前供应商适配器仍读取 `modules/cloud` 中的共享媒体模型，并保留必要的平台工具和请求诊断依赖。这些依赖已在架构测试中列为过渡白名单；供应商之间互相导入、`cloud/core` 反向导入供应商目录均被禁止。

## 当前遗留边界

- `pages` 和部分旧 `services` 仍直接使用控制器、仓储和供应商组合根，属于兼容层，暂不整体重写。
- 少量功能仍通过 `Modular.get` 取得全局对象；新增业务应使用构造函数注入。
- 部分仓储仍直接访问 `GStorage.setting`，后续以 `TypedSettings` 或明确的 repository 接口封装。
- `features -> pages` 现有历史依赖保留在架构测试白名单中，不允许新增；迁移完成后应逐项删除白名单。

## 后续顺序

1. 将 `modules/cloud` 的共享模型收拢到公共端口或领域目录，缩小供应商过渡白名单。
2. 继续把 `Modular.get` 从业务流程移到应用装配层。
3. 为本地库、播放器和各网盘端口补充用例级测试，再逐步退化旧页面控制器。
4. 控制器和网盘模块完成运行时回归后，再更新架构测试白名单和本文迁移状态。
