# 海报技术标签位置调整设计

## 目标

把 `ImmersiveMediaCard` 左上角常驻的分辨率、片源、编码、HDR、音频等技术标签移入底部信息面板，避免遮挡海报主体，同时保留完整技术信息。

## 已确认方案

- 海报默认状态不显示技术标签，保持封面构图完整。
- 鼠标悬停、键盘聚焦或 Android TV 聚焦时，技术标签随现有底部信息面板显示。
- `overlayMode == ImmersiveMediaCardOverlayMode.always` 的入口继续常驻显示底部信息面板和技术标签。
- 技术标签位于评分、年份等详情下方，来源、字幕和刮削状态按钮上方。
- 右上角资源菜单、标题、评分、普通状态按钮和卡片交互不变。

## 实现边界

- 只调整共享组件 `lib/features/library/presentation/immersive_media_card.dart` 的现有 `MediaTechnicalBadgeRow` 布局位置。
- 复用现有标签解析、颜色、顺序和换行能力，不新增组件、状态或依赖。
- 删除卡片最外层 Stack 中左上角的常驻 `Positioned`，在 `_buildOverlay` 的 `GlassSurface` 内容列中复用同一标签行。
- 空技术标签列表不增加间距。
- 不修改海报 2:3 比例、深色裁边、图片来源和回退顺序、海报缓存、Android TV 专用 0.78 布局或原始媒体文件。

## 验证

- 更新 `test/library_presentation_components_test.dart`：验证标签属于底部 `GlassSurface`，默认 hover 模式不可见，悬停或聚焦后可见，always 模式常驻，空列表不占位。
- 运行共享卡片、网盘海报墙和媒体库聚焦测试，再运行完整 `flutter test --no-pub`、`flutter analyze --no-pub`、格式和差异检查。
- 构建并安装 Windows 2.1.179 Inno 测试版，实测默认海报无遮挡、悬停信息完整、菜单及卡片操作正常。
- 不生成 MSIX、Android 手机或 Android TV 产物，不执行 Git commit。
