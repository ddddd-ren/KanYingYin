# Errors

Command failures and integration errors.

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
