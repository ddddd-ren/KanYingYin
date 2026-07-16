# 看影音 2.0 身份断代与零残留实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 发布使用全新签名主体和 MSIX 包身份的看影音 2.0，并让所有 Git 跟踪文件中的旧项目名称实现零匹配。

**Architecture:** 使用字节级仓库测试约束源码、测试、文档和资源零残留。删除已无业务调用的旧编码协议 API，切换为 `com.kanyingyin.player.v2` 与 `CN=KanYingYin`，签名证书及加密凭据只保存在当前用户私有目录。

**Tech Stack:** Flutter 3.41.9、Dart、PowerShell Certificate Provider、MSIX、flutter_test。

---

### Task 1: 全仓库零残留契约

**Files:**
- Create: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/runtime_identity_residue_test.dart`
- Modify: `test/encoding_utils_test.dart`
- Modify: `test/dead_online_code_test.dart`
- Modify: `docs/**/*.md`

- [ ] **Step 1:** 新增字节级失败测试，扫描 `git ls-files` 返回的每个文件并禁止旧名称。
- [ ] **Step 2:** 运行目标测试，确认因证书主体、旧协议、测试和历史文档而失败。
- [ ] **Step 3:** 清理测试禁止词和历史文档，删除旧协议兼容测试与旧术语。
- [ ] **Step 4:** 重跑目标测试并通过。

### Task 2: 新 MSIX 身份与版本

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`

- [ ] **Step 1:** 测试要求版本 `2.0.0+20000`、MSIX `2.0.0.0`、Identity `com.kanyingyin.player.v2`、Publisher `CN=KanYingYin`。
- [ ] **Step 2:** 运行测试确认旧身份导致失败。
- [ ] **Step 3:** 更新身份、版本及面向普通用户的断代安装说明。
- [ ] **Step 4:** 重跑版本与身份测试并通过。

### Task 3: 删除旧协议并创建新证书

**Files:**
- Modify: `lib/utils/encoding_utils.dart`
- Modify: `lib/utils/utils.dart`
- Create outside repository: `%USERPROFILE%\.kanyingyin\signing\certificate.pfx`
- Create outside repository: `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml`

- [ ] **Step 1:** 确认旧协议 API 无业务调用后删除编码包装，仅保留文件哈希。
- [ ] **Step 2:** 生成 `CN=KanYingYin` 代码签名证书，使用随机密码导出 PFX，并用 DPAPI 加密保存 SecureString。
- [ ] **Step 3:** 验证证书 Subject、私钥、有效期和 PFX 可读取，确保仓库不含密码或证书文件。

### Task 4: 完整验证与提交

**Files:**
- Verify: all changed files

- [ ] **Step 1:** 运行 `flutter test` 和 `flutter analyze`。
- [ ] **Step 2:** 运行 `flutter build windows --release --no-pub`。
- [ ] **Step 3:** 使用私有凭据生成 MSIX，验证 Manifest、签名和全仓库零残留。
- [ ] **Step 4:** 检查关键 diff，仅提交本轮相关文件。
