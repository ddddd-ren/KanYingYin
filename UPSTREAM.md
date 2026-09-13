# 上游来源与项目沿革

本文说明看影音（KanYingYin）与上游开源项目的关系、代码来源，以及本仓库的署名变更历史。

## 一、与 Kazumi 的关系

看影音在项目初期参考了 [Predidit/Kazumi](https://github.com/Predidit/Kazumi)（GPL-3.0）的架构思路与部分实现。Kazumi 是一款成熟的 Flutter 动漫播放器，看影音在其基础上重新定位为**面向本地与个人网盘的媒体库与播放器**。

### 代码重合度（可复核）

以 2026-09 的仓库状态与 Kazumi 上游副本比对：

| 项目 | 看影音 | Kazumi |
| --- | --- | --- |
| `lib/` 下 Dart 文件数 | 433 | 226 |
| 同路径文件数 | 50 | 50 |
| 其中内容完全相同 | **2** | — |
| 其中内容不同 | 48 | — |

内容完全相同的两个文件为 `lib/shaders/shaders_controller.g.dart`（代码生成产物）与 `lib/utils/proxy_utils.dart`。

**结论**：看影音在目录结构上沿用了上游的分层思路，但绝大多数文件已重写或大幅改写。433 个 Dart 文件中，仅 2 个与上游逐字节一致。

### 上游未包含的功能

以下功能为看影音新增，上游 Kazumi 不具备：

- 本地文件夹媒体库：扫描、作品识别、季集匹配与手动修正
- 四类个人网盘接入：OpenList、夸克、百度、迅雷（按只读方式访问）
- 加密配置迁移（`.kyyconfig`）与导入失败自动回滚
- 脱敏运行日志（保留最近 10 份）与诊断 ZIP 导出
- Windows C++ Runner 与 Inno Setup 安装包交付流程
- GitHub Actions 双平台质量门禁（格式检查、静态分析、单元测试、构建）

### 上游移除的能力

看影音不含公共在线影视搜索、插件规则、WebView 视频解析或在线评论功能。这是定位差异，不是能力缺失。

## 二、第三方组件

| 组件 | 用途 | 许可 |
| --- | --- | --- |
| [media-kit](https://github.com/media-kit/media-kit)（经 Predidit fork） | Flutter 媒体播放能力 | MIT |
| [mpv](https://mpv.io/) | 底层音视频播放与渲染 | LGPL-2.1+ / GPL-2.0+ |
| [Anime4K](https://github.com/bloc97/Anime4K) | 实时动漫画质增强着色器 | MIT |
| [Flutter](https://flutter.dev/) | 应用框架（子模块） | BSD-3-Clause |
| [TMDB](https://www.themoviedb.org/) | 影视元数据 API | 使用条款见官网 |
| [Mi Sans](https://hyperos.mi.com/font/en/details/sc/) | 应用内嵌字体 | 见字体授权 |
| [OpenList](https://github.com/OpenListTeam/OpenList) | 用户自有网盘文件访问接口 | 见项目授权 |

第三方组件的完整许可清单见 `docs/third-party-shader-review.md` 与应用内「关于」页。

**看影音使用 TMDB API，但不受 TMDB 认可或认证。**

## 三、开发方式说明

本项目在开发过程中使用了 AI 编码工具辅助实现，由项目维护者负责：

- 需求定义与功能取舍
- 技术选型与架构决策
- 验收标准制定（`flutter analyze` 无错误、`flutter test` 通过、双平台构建成功、播放器实机可用）
- 代码审查、版本发布与交付验收

工程约束与验收标准记录在 [`AGENTS.md`](AGENTS.md)。

## 四、署名变更历史

本仓库的 Git 身份配置在项目初期继承自上游克隆，导致 2026-07-17 至 2026-09-13 期间的提交署名为 `Kazumi Dev <kazumi@project.local>`，与实际提交者不符。

2026-09-13 执行了历史重写，将该区间内全部提交的署名统一为仓库所有者：

```
ddddd-ren <ddddd-ren@users.noreply.github.com>
```

说明：

- 提交**内容未发生任何变更**，仅作者姓名与邮箱被改写（重写前后 HEAD 的 tree hash 一致）
- 全部 830 次提交的 commit hash 因此发生变化
- 16 个标签已同步重写并重新推送，15 个 Release 指向正常
- 重写前的完整镜像备份保留在本地，未上传

## 五、许可证

本项目以 [GNU 通用公共许可证 v3.0](LICENSE) 发布。分发修改版或安装包时，请继续遵守 GPL-3.0，并向接收者提供对应版本的完整源代码和许可证信息。
