# 来源剧名统一实施计划

**目标：** 网盘媒体库及本地来源卡片确定作品显示名，分类、详情、播放、历史、收藏均沿用对应来源的最终结果。

**实现：** 复用已有来源分组、媒体库适配器与持久化索引；显示名与媒体身份分别传递。来源不可读时保留最后可用标题和用户记录，不修改原始视频。

**技术：** Flutter 3.41.9、MobX、现有媒体索引及 Hive 存储，不增加依赖。

## 工作步骤

- [x] 本地来源标题由同一分组器和目录改名记录生成；统一媒体库和详情透传结果，覆盖 TMDB 标题不同名、手工改名及分组冲突。
- [x] 网盘沿用 CloudResourceMediaLibraryAdapter；标题变更期间废弃旧快照，保留来源真实季名。
- [x] 历史列表和恢复播放按媒体稳定身份读取当前来源标题；多重匹配或来源缺失保留快照，测试进度与记录身份，兼容快照读取失败时的两种旧入口身份。
- [x] 播放偏好改用稳定作品关联并兼容旧标题键；覆盖同源跨集、改名和跨来源隔离，备份导入兼容新旧偏好键。
- [x] 同步版本 2.1.222+20222、安装器与普通用户更新文案；保留全部已有工作区改动，不提交 Git。
- [x] 对抗式审查；运行相关回归、全量 flutter test、flutter analyze 和 Windows Release 构建；生成 Inno Setup EXE 到桌面，核对版本、哈希和签名状态。

## 命令与验收

`D:\flutter\bin\flutter.bat test --no-pub --concurrency 2 --reporter expanded`

`D:\flutter\bin\flutter.bat analyze --no-pub`

`& .\tool\windows\build_exe_release.ps1 -KeepIntermediateArtifacts`

来源显示「光阴之外」时所有作品标题均为「光阴之外」；来源本身含「第 2 季」时原样保留。首次进入分类、重启和离线读取缓存时一致。来源已删除或匹配不唯一时保留旧记录，分组拆分导致用户状态无法唯一对应时保留待关联记录。

## 最终验证（2026-10-11）

- 冻结代码后的全量测试：2277 项通过；日志 `build/source_title_frozen_full_tests.log`。第一次全量运行期间补齐了历史回退函数，发生一次旧编译快照加载失败，冻结后重新完整运行通过。
- 静态分析：`No issues found`；日志 `build/source_title_final_analyze.log`。
- Windows Release 构建和 Inno Setup 编译通过；日志 `build/source_title_windows_package.log`。
- Release 主程序与桌面安装器均为 2.1.222，Flutter 构建输出与 Release 内的 `app.so` 哈希相同；两处 EXE 的签名状态均为 `NotSigned`。
- 桌面安装包：`C:/Users/asus/Desktop/看影音-2.1.222-测试版-安装程序.exe`，70,080,144 字节。
- 安装包 SHA-256：`1DBB86971756491322E4B3582BC852140653AC24493A08F835FF38BDA3E7006F`。
- Release 主程序 SHA-256：`38005FDAF34D1D03412EB589DE864000E75973B9A39E3B4C062DDE72C7B65FDA`。
- 对抗式审查发现的新偏好键备份映射、来源快照不可用时的旧历史身份遗漏均已修复，并有可运行回归。最终 `git diff --check` 通过，未执行 Git 提交。
- 未安装新包，已安装主程序仍为 2.1.221；未进行实机播放及实际用户媒体界面的验证。歧义旧偏好与收藏保留原记录，无法自动确定归属时不迁移。

## 2.1.223 反馈修复（2026-10-11）

- 用户在已安装 2.1.222 中仍看到分类卡片「光阴之外 S01」、来源卡片「光阴之外」。本轮版本更新前确认 EXE 与安装登记均为 2.1.222，路径 `D:/看影音/kanyingyin.exe`，无旧 MSIX。
- 直接根因是 `UnifiedMediaCardInfoBuilder.forSeries` 在最终展示层重新追加季号；来源适配器的标题本已正确。上一轮只验证模型和详情，遗漏带季号数据的悬停浮层。
- 删除展示层的额外命名，直接使用 `series.title`；来源已有 `S01` 或中文季名时原样保留。本轮未调整 71/38 集的统计口径。
- 修复前单位回归出现 4 个预期失败，真实 Windows 分类悬停浮层出现 2 个预期失败；修复后 8 个相关测试文件共 181 项通过，独立审查复跑标题及页面 24 项通过，未发现阻断问题。
- 已同步 2.1.223+20223、Inno 安装器及普通用户更新文案。
- 冻结代码后的全量测试 2286 项全部通过；日志 `build/source_title_223_full_tests.log`。静态分析无问题；日志 `build/source_title_223_analyze.log`。
- Windows Release 构建和 Inno 编译通过，Release 与安装器版本均为 2.1.223；构建脚本校验 Flutter 输出与 Release 内的 `app.so` 哈希一致。日志 `build/source_title_223_windows_package.log`。
- 桌面安装器 `C:/Users/asus/Desktop/看影音-2.1.223-测试版-安装程序.exe`，70,080,976 字节，签名状态 `NotSigned`，SHA-256 `B12902EAB1677E8C692F0A1CAC9930C7CF52D99EE5CC11D27A3ECC5EE0096277`。
- Release 主程序 SHA-256 `86B797D29335690985DE9DB57CF78B34070C3B5029E64764BE2E44275F3C9FA5`。
- 已通过 Computer Use 启动新 Release 程序；随后用户按 Esc 停止自动操作，实机界面与播放未完成核查。未安装新包，未执行 Git 提交。
