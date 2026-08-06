# Formal Installer User Selected Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the formal Windows EXE installer and first-run storage defaults independent of drive D while keeping user-selected install, data, and cache directories.

**Architecture:** Inno Setup supplies a safe current-user default and keeps its directory wizard enabled. `StoragePathResolver` uses `path_provider` locations for first-run fallback and preserves configured paths and last successful paths during migration. Tests assert both installer and runtime contracts, while release copy describes the user-visible behavior.

**Tech Stack:** Flutter 3.41.9, Dart, PowerShell, Inno Setup, Flutter tests.

---

### Task 1: Lock the installer and storage contracts with failing tests

**Files:**
- Modify: `test/windows_exe_release_packaging_test.dart`
- Modify: `test/storage_path_resolver_test.dart`

- [ ] **Step 1: Add assertions for a user-selectable EXE default**

Assert that `tool/windows/installer/看影音测试版.iss` contains `DefaultDirName={code:DefaultInstallDir}`, contains `{localappdata}` and does not contain `Result := 'D:\\看影音'`.

- [ ] **Step 2: Add assertions for storage fallback**

Assert that `lib/services/storage/storage_path_resolver.dart` does not use a fixed `Directory(r'D:\\看影音')` as the Windows default and that the existing migration failure test keeps `lastSuccessfulDataRoot` and `lastSuccessfulCacheRoot`.

- [ ] **Step 3: Run the focused tests**

Run `D:\flutter\bin\flutter.bat test --no-pub test\\windows_exe_release_packaging_test.dart test\\storage_path_resolver_test.dart`.

Expected: FAIL because the installer still returns `D:\\看影音` when D exists and the resolver still contains the fixed D path.

### Task 2: Implement safe defaults and preserve migration behavior

**Files:**
- Modify: `tool/windows/installer/看影音测试版.iss`
- Modify: `lib/services/storage/storage_path_resolver.dart`

- [ ] **Step 1: Change the Inno Setup default**

Replace the `DefaultInstallDir` function body with:

```pascal
function DefaultInstallDir(Param: String): String;
begin
  Result := ExpandConstant('{localappdata}\\Programs\\看影音');
end;
```

- [ ] **Step 2: Remove the fixed D drive runtime default**

Set the first-run `defaultRoot` to `legacyData.parent` and set `dataRoot` under that root. Set `cacheRoot` to `legacyCache.path`. Keep configured paths and `lastSuccessful*` fallback behavior unchanged.

- [ ] **Step 3: Run the focused tests**

Run the focused command from Task 1.

Expected: PASS, including migration failure preservation.

### Task 3: Update user-facing copy and release contracts

**Files:**
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`

- [ ] **Step 1: Replace D-drive-specific wording**

State that the installer starts in the current-user directory and the user can choose another installation directory; state separately that application data and cache can be selected in Settings.

- [ ] **Step 2: Preserve platform separation**

Keep Android copy free of Windows installer and drive-path details.

- [ ] **Step 3: Run copy and version tests**

Run `D:\flutter\bin\flutter.bat test --no-pub test\\version_consistency_test.dart test\\release_config_contract_test.dart test\\version_history_current_test.dart`.

Expected: PASS.

### Task 4: Full verification and release handoff

**Files:**
- Review only: all files changed above.

- [ ] **Step 1: Format and inspect**

Run `D:\flutter\bin\dart.bat format lib test`, `git diff --check`, and `git status --short`; confirm no unrelated files are staged.

- [ ] **Step 2: Run quality gates**

Run `D:\flutter\bin\flutter.bat test --no-pub` and `D:\flutter\bin\flutter.bat analyze --no-pub`; both must exit 0.

- [ ] **Step 3: Build and validate Windows EXE**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool\\windows\\build_exe_release.ps1`; verify release executable and installer product version match the release version, installer is copied to the desktop, and the installer is not signed unless a code-signing certificate is explicitly configured.

- [ ] **Step 4: Commit only related changes**

Run `git add` for the installer, storage resolver, tests, release notes, version history, README, and approved design/plan files, then commit with a concise Chinese message.
