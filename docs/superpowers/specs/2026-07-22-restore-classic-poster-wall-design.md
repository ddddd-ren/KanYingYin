# 恢复改版前海报墙

本规格已由 `2026-07-22-player-exit-and-classic-poster-wall-design.md` 取代。合并规格增加播放器退出生命周期修复，并保留本文定义的海报墙验收标准。

本文定义如何在保留新版桌面框架的同时，精确恢复提交 `1585d82` 之前的本地与网盘海报墙。

## 目标

恢复改版前的整张海报覆盖式卡片、悬停信息层和网格密度。新版主题、导航、工具栏及设置命名保持不变。

## 变更范围

仅反向恢复提交 `1585d82` 对以下生产文件的修改：

- `lib/features/library/presentation/immersive_media_card.dart`
- `lib/features/library/presentation/library_media_grid.dart`
- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`

同步更新以下测试文件，使断言重新描述改版前的行为：

- `test/library_presentation_components_test.dart`
- `test/cloud_resources_page_test.dart`

## 卡片显示

卡片使用海报填满全部可用区域，不保留海报下方的常驻信息区。标题、字幕、详情和全部徽章位于海报上方的渐变信息层中。

本地和网盘卡片继续使用相同的 `ImmersiveMediaCard`。点击、长按、右键、资源菜单、徽章操作、加载状态及播放入口保持现有行为。

## 悬停动画

普通媒体库卡片默认隐藏渐变信息层。鼠标进入卡片时，信息层使用 `AnimatedOpacity` 在 `160 ms` 内按 `Curves.easeOut` 显示；鼠标离开时按相同参数隐藏。

悬停期间叠加透明度为 `0.04` 的白色蒙层。卡片不使用新版边框变色、阴影抬升或居中播放圆形按钮。

当 `overlayMode` 为 `always` 时，信息层持续显示。加载状态继续使用透明度为 `0.34` 的主题遮罩和居中的进度指示器，右上角操作菜单保持可见。

## 网格尺寸

本地与网盘海报墙统一恢复以下参数：

- `maxCrossAxisExtent: 300`
- `childAspectRatio: 0.68`
- `crossAxisSpacing: 12`
- `mainAxisSpacing: 12`

窗口宽度变化时仍由 `SliverGridDelegateWithMaxCrossAxisExtent` 自动调整列数。

## 明确保留的新版界面

以下内容不随海报墙恢复而回退：

- 雾蓝品牌主题和中性内容表面
- 宽屏侧栏、紧凑导航栏和窄屏底部导航
- 本地与网盘工具栏的更多操作菜单
- “本地媒体库”“网盘媒体库”和“设置”命名
- 播放器控件、动画、字幕、选集、硬件解码与 Anime4K 行为

本次不处理已单独诊断的“从播放页返回后卡死”问题，避免把播放器生命周期修复混入海报墙回退。

## 测试与验收

测试先恢复以下预期，并确认它们在生产代码修改前失败：

1. 信息层初始透明度为 `0`，悬停后变为 `1`
2. 信息层包含标题、字幕、详情和全部徽章
3. 卡片不再包含新版常驻信息区和居中播放按钮
4. 本地与网盘网格参数均为 `300` 和 `0.68`
5. 加载遮罩、菜单、点击、长按和右键操作保持有效

实现完成后运行相关组件测试、完整 `flutter test`、`flutter analyze` 和 Windows Release 构建。

## 版本与交付

当前已安装版本为 `2.1.36.0`。交付版本升级为应用版本 `2.1.37+20137` 和 MSIX 版本 `2.1.37.0`，同步更新版本历史与发布说明。

使用 `tool/windows/build_signed_release.ps1` 构建并签名安装包。最终验证签名状态、证书指纹、清单身份、版本、架构和桌面副本哈希。

## 隔离与回滚

全部修改保留在 `D:\KanYingYin\.worktrees\ui-refresh-v1` 的 `codex/ui-refresh-v1` 分支。未获得明确指示前，不合并到 `main`，也不删除当前 2.1.36 安装包。
