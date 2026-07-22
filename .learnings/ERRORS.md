# Errors

Command failures and integration errors.

---

## [ERR-20260717-001] powershell_relative_path

**Logged**: 2026-07-17T02:10:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
Windows PowerShell 5.1 的运行时不提供 `System.IO.Path.GetRelativePath`。

### Error
```text
Method invocation failed because [System.IO.Path] does not contain a method named 'GetRelativePath'.
```

### Context
- 在只读核对媒体压缩包与已解压字幕时计算临时文件相对路径。
- `finally` 已正常清理临时目录，媒体文件未被修改。

### Suggested Fix
在 Windows PowerShell 5.1 中通过已知根路径长度截取相对路径，或使用 URI 相对路径算法。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-17T02:10:00+08:00
- **Notes**: 改用根路径前缀截取方式后重新执行比对。

---

## [ERR-20260717-002] agent_reach_cli_missing

**Logged**: 2026-07-17T02:15:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
`agent-reach` 与 `mcporter` 命令未安装，无法按首选通道执行网页搜索。

### Error
```text
The term 'agent-reach' is not recognized.
The term 'mcporter' is not recognized.
```

### Context
- 为媒体字幕改名核对 TMDB 简体中文标题。
- 本地媒体文件尚未开始修改。

### Suggested Fix
使用可用的只读网页请求作为降级通道，或后续安装 Agent Reach CLI。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-17T02:15:00+08:00
- **Notes**: 本轮改用只读网页请求继续核对。

---

## [ERR-20260717-003] powershell_environment_check_parser

**Logged**: 2026-07-17T02:30:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
批量环境检查脚本在 `foreach` 表达式后直接接管道，触发 PowerShell 空管道解析错误。

### Error
```text
An empty pipe element is not allowed.
```

### Context
- 检查 Agent Reach 安装依赖时发生。
- 尚未执行任何安装命令。

### Suggested Fix
先将 `foreach` 输出赋给变量，再将变量传给 `ConvertTo-Json`。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-17T02:30:00+08:00
- **Notes**: 拆分环境检查命令后继续。

---

## [ERR-20260717-004] pip_show_expected_missing

**Logged**: 2026-07-17T02:32:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
`pip show` 查询未安装包时会返回退出码 1，导致并行环境检查整体被标记失败。

### Error
```text
pip show pipx agent-reach returned exit code 1 because the packages were absent.
```

### Context
- Agent Reach 安装前置检查。
- 这是预期的“未安装”状态，不是 pip 故障。

### Suggested Fix
检查可选包时显式接纳退出码 1，或使用 Python 包元数据 API判断是否安装。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-17T02:32:00+08:00
- **Notes**: 后续拆分检查并将缺包视为正常结果。

---

## [ERR-20260717-005] agent_reach_local_wheel_duplicate

**Logged**: 2026-07-17T02:35:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
从本地 Agent Reach 技能副本安装时，Hatch wheel 构建因重复包含指南文件失败。

### Error
```text
ValueError: A second file is being added to the wheel archive at the same path: agent_reach/guides/setup-exa.md
```

### Context
- `pipx` 已成功安装。
- 失败发生在本地源码元数据生成阶段，Agent Reach 尚未安装。

### Suggested Fix
按官方安装文档改用 GitHub 主分支归档，避免本地技能副本的过期打包配置。

### Metadata
- Reproducible: yes
- Related Files: C:/Users/asus/.agents/skills/agent-reach/pyproject.toml

### Resolution
- **Resolved**: 2026-07-17T02:35:00+08:00
- **Notes**: 改用官方 GitHub 归档继续安装。

---

## [ERR-20260717-006] agent_reach_windows_upstream_install

**Logged**: 2026-07-17T02:40:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
Agent Reach 1.5.0 在 Windows 自动安装基础上游工具时未正确调用 npm/winget。

### Error
```text
mcporter install failed: [WinError 2]
gh CLI not found
yt-dlp not installed
```

### Context
- Agent Reach 核心命令已安装成功。
- Windows 已有 npm 与 winget，适合手动补齐用户级依赖。

### Suggested Fix
使用 `npm install -g mcporter`、`pipx install yt-dlp` 和 `winget install GitHub.cli --scope user`，然后重新配置 Exa 并运行 doctor。

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-07-17T02:50:00+08:00
- **Notes**: 手动安装并验证 mcporter、yt-dlp 与 GitHub CLI，Exa 搜索恢复可用。

---

## [ERR-20260717-007] mcporter_call_syntax_drift

**Logged**: 2026-07-17T02:52:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
Agent Reach 技能中的 mcporter 函数表达式示例在 mcporter 0.12.3 下被错误解析。

### Error
```text
MCP error -32000: Connection closed
exa-web-search-exa-query-agent appears offline
```

### Context
- Exa home 配置存在，Agent Reach doctor 将 Exa 标记为可用。
- 失败发生在直接调用搜索工具时。

### Suggested Fix
按当前 `mcporter call --help` 使用 0.12.3 支持的显式服务器、工具与参数格式。

### Metadata
- Reproducible: yes
- Related Files: C:/Users/asus/.mcporter/mcporter.json

### Resolution
- **Resolved**: 2026-07-17T02:55:00+08:00
- **Notes**: 改用显式 `server.tool` 加 `key=value` 参数格式，Exa 搜索调用成功。

---

## [ERR-20260717-008] gh_device_auth_network_timeout

**Logged**: 2026-07-17T03:00:00+08:00
**Priority**: medium
**Status**: in_progress
**Area**: infra

### Summary
GitHub CLI 设备授权轮询 Token 接口时直连超时。

### Error
```text
failed to authenticate via web browser: Post https://github.com/login/oauth/access_token: connection timed out
```

### Context
- 浏览器可打开 GitHub 设备授权页面。
- CLI 连接目标为 GitHub 公网地址，未使用浏览器的系统代理。

### Suggested Fix
读取 Windows 用户代理设置，为本轮 `gh auth login` 设置 `HTTPS_PROXY` 后重新授权。

### Metadata
- Reproducible: unknown
- Related Files: none

---

## [ERR-20260717-009] gh_wrong_oauth_client_id

**Logged**: 2026-07-17T03:10:00+08:00
**Priority**: high
**Status**: in_progress
**Area**: infra

### Summary
从 gh 二进制提取的第一个 OAuth Client ID 生成令牌后，GitHub API 校验返回 401。

### Error
```text
error validating token: HTTP 401: Bad credentials
```

### Context
- 用户已在 GitHub 设备页面批准授权。
- 无效令牌未被 gh 保存，临时加密设备状态已删除。

### Suggested Fix
核对 gh 二进制内多个 Client ID 的用途，使用 GitHub.com CLI 对应的正确 Client ID 重新执行设备授权。

### Metadata
- Reproducible: yes
- Related Files: GitHub CLI gh.exe

---

## [ERR-20260623-001] flutter_build_windows

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
KanYingYin Release 构建在 Dart VM/assemble 阶段失败，随后 `flutter pub get` 也出现 VM 崩溃。

### Error
```text
runtime/vm/runtime_entry.cc: error: hit null error with cid 92
MSB8066: flutter_windows.dll.rule / flutter_assemble.rule exited with code 1

===== CRASH =====
ExceptionCode=-1073741819
Failed to update packages.
```

### Context
- Command attempted: `flutter build windows --release`
- Follow-up command attempted: `flutter pub get`
- Environment: Flutter 3.41.9, Dart 3.11.5, Windows x64
- Side effect: Flutter dependency resolution rewrote `pubspec.lock` hosted URLs to mirror URLs until restored.

### Suggested Fix
Restore `pubspec.lock`, use isolated APPDATA, run `flutter pub get --offline --enforce-lockfile`, then build with `flutter build windows --release --no-pub`.

### Metadata
- Reproducible: unknown
- Related Files: pubspec.lock, pubspec.yaml

### Resolution
- **Resolved**: 2026-06-23T03:12:01+08:00
- **Commit/PR**: 14223b4
- **Notes**: Locked offline pub get and `--no-pub` release build completed successfully after cache fixes.

---

## [ERR-20260623-002] media_kit_libmpv_download

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
`media_kit_libs_windows_video` 的 libmpv archive 下载为 0 字节并导致 SHA 校验失败。

### Error
```text
D:/KanYingYin/build/windows/x64/mpv-dev-x86_64-20251210-git-ad59ff1.7z
Integrity check failed, please try to re-build project again.
```

### Context
- Command attempted: `flutter build windows --release --no-pub`
- Archive path: `build\windows\x64\mpv-dev-x86_64-20251210-git-ad59ff1.7z`
- Broken file size: 0 bytes
- Plain curl failed with Schannel certificate revocation check error.

### Suggested Fix
Delete the 0-byte archive, run `curl.exe --ssl-no-revoke -L --fail --retry 3` against the GitHub release URL, verify SHA256 `53212bb8886d76d041ecd023a29e6213ada6fb5afedb8970610b396435833b99`, then rerun build.

### Metadata
- Reproducible: yes
- Related Files: windows/flutter/ephemeral/.plugin_symlinks/media_kit_libs_windows_video/windows/CMakeLists.txt

### Resolution
- **Resolved**: 2026-06-23T03:05:30+08:00
- **Commit/PR**: 14223b4
- **Notes**: Manual download with `--ssl-no-revoke` produced an 11,088,708 byte archive with the expected SHA256.

---

## [ERR-20260623-003] webview_windows_nuget

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
`webview_windows` CMake stage reported NuGet missing and build exited during first dependency setup.

### Error
```text
Nuget is not installed.
Attempting to download nuget.
Build process failed.
```

### Context
- Command attempted: `flutter build windows --release --no-pub`
- NuGet was downloaded to `build\windows\x64\nuget.exe`
- Required packages `Microsoft.Web.WebView2` and `Microsoft.Windows.ImplementationLibrary` were created under `build\windows\x64\packages`.

### Suggested Fix
Verify `nuget.exe` SHA256 `852b71cc8c8c2d40d09ea49d321ff56fd2397b9d6ea9f96e532530307bbbafd3` and package folders, then rerun Release build.

### Metadata
- Reproducible: unknown
- Related Files: windows/flutter/ephemeral/.plugin_symlinks/webview_windows/windows/CMakeLists.txt

### Resolution
- **Resolved**: 2026-06-23T03:10:13+08:00
- **Commit/PR**: 14223b4
- **Notes**: After NuGet and WebView packages existed, the next Release build completed successfully.

---
