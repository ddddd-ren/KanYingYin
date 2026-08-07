# 第三方着色器来源审查

## LuckyPuppy514/MPV_Glsl_Running_Mode_Cache

- 仓库：`https://github.com/LuckyPuppy514/MPV_Glsl_Running_Mode_Cache`
- 固定审查提交：`73f88a977ec50945be12822bda1141426216d6d2`
- 提交时间：2022-04-26
- 许可：MIT
- 内容：Lua 运行模式缓存、`input.conf` 和多个来源的 GLSL 文件。

看影音不会执行该仓库的 Lua，也不会从仓库在线下载并覆盖播放器资源。现有 Anime4K 资源继续随应用打包；应用升级时，只允许 `assets/shaders/` 直属目录中的 `.glsl` 文件通过临时文件和回滚机制更新到应用数据目录。其他脚本、配置、动态库和可执行文件均不进入安装链路。
