# 夸克 Cookie 原生网盘媒体库实施计划

> **执行约束：** 当前任务内联执行，禁止创建子智能体。逐项使用 `superpowers:test-driven-development`，每个阶段独立提交。

**目标：** 在看影音 Windows Flutter/MSIX 应用中原生完成夸克 Cookie 登录、媒体库扫描、在线播放和手动分享转存闭环，同时保持 OpenList 与本地媒体行为不变。

**架构：** 以 `CloudRemoteRef` 和 `CloudProviderRegistry` 重建通用云盘边界；夸克拆分为请求策略、响应解析、只读驱动和独立分享转存服务。所有稳定 ID/路径进入普通索引，Cookie 和短期令牌严格隔离在安全存储或请求内存。

**技术栈：** Flutter 3.41.9、Dart、Flutter Modular、MobX、Dio、Hive CE、flutter_secure_storage、media-kit、MSIX。

---

### 任务 1：协议证据与脱敏夹具

**文件：**
- 新建：`test/fixtures/quark/account_success.json`
- 新建：`test/fixtures/quark/directory_page_1.json`
- 新建：`test/fixtures/quark/directory_empty.json`
- 新建：`test/fixtures/quark/playback_success.json`
- 新建：`test/fixtures/quark/share_token_success.json`
- 新建：`test/fixtures/quark/share_detail_success.json`
- 新建：`test/fixtures/quark/save_task_success.json`
- 新建：`test/fixtures/quark/task_completed.json`
- 修改：`docs/superpowers/specs/2026-07-15-openlist-cloud-library-design.md`
- 新建：`docs/superpowers/specs/2026-07-19-quark-cookie-cloud-library-design.md`

- [ ] 写入只含 `account_fixture`、`fid_fixture_*`、`.invalid` URL 和虚构时间的 JSON。
- [ ] 用 `rg -n "Cookie:|__puus|stoken_fixture|https://(?![^ ]*\.invalid)" test/fixtures/quark` 人工审查敏感内容。
- [ ] 运行 JSON 解码测试，预期全部夹具可解析。
- [ ] 提交：`文档：确定夸克原生接入协议与计划`。

### 任务 2：CloudRemoteRef 与旧索引迁移

**文件：**
- 新建：`lib/services/cloud/cloud_remote_ref.dart`
- 修改：`lib/services/cloud/cloud_drive_client.dart`
- 修改：`lib/modules/cloud/cloud_source.dart`
- 修改：`lib/modules/cloud/cloud_media_index_item.dart`
- 修改：`lib/repositories/cloud_media_index_repository.dart`
- 修改：`lib/services/cloud/cloud_media_indexer.dart`
- 测试：`test/cloud_remote_ref_test.dart`
- 测试：`test/cloud_media_index_repository_test.dart`

- [ ] RED：断言 `CloudRemoteRef(id: 'fid', path: '/影片')` 值相等且可 JSON 往返；旧来源 `rootPaths` 与旧 `subtitlePaths` 可迁移。
- [ ] 运行 `D:\flutter\bin\flutter.bat test test/cloud_remote_ref_test.dart test/cloud_media_index_repository_test.dart --no-pub`，预期因类型/迁移缺失失败。
- [ ] GREEN：新增 `CloudRemoteRef`，来源保存 `rootRefs`，索引字幕保存 `List<CloudRemoteRef>`，旧字段以路径作为回退 ID。
- [ ] 将驱动、扫描队列和播放目标签名改为远程引用，保持 OpenList 路径语义。
- [ ] 运行目标测试和 `test/cloud_media_indexer_test.dart`，预期通过。
- [ ] 提交：`重构：新增云盘强类型远程引用`。

### 任务 3：提供商注册器和 OpenList 回归

**文件：**
- 新建：`lib/services/cloud/cloud_provider_registry.dart`
- 修改：`lib/services/cloud/openlist/openlist_client.dart`
- 修改：`lib/providers/cloud_library_controller.dart`
- 修改：`lib/services/cloud/cloud_playback_resolver.dart`
- 测试：`test/cloud_provider_registry_test.dart`
- 测试：`test/openlist_client_test.dart`
- 测试：`test/cloud_library_controller_test.dart`
- 测试：`test/cloud_playback_resolver_test.dart`

- [ ] RED：断言注册器创建 OpenList 客户端、规范化地址、合并用户名密码、允许自签名并返回 OpenList 专属错误。
- [ ] 运行四个目标测试，预期因注册器缺失失败。
- [ ] GREEN：实现提供商描述与工厂；从控制器/解析器移除来源 `switch` 和 OpenList 文案。
- [ ] 适配 OpenList 的 `CloudRemoteRef.path`，旧索引播放不变。
- [ ] 运行 OpenList 与云盘控制器/播放全量测试，预期通过。
- [ ] 提交：`重构：集中注册网盘提供商`。

### 任务 4：Cookie 生命周期与日志安全

**文件：**
- 修改：`lib/services/cloud/cloud_credential_store.dart`
- 修改：`lib/providers/cloud_library_controller.dart`
- 修改：`lib/utils/log_sanitizer.dart`
- 测试：`test/cloud_library_controller_test.dart`
- 测试：`test/cloud_source_repository_test.dart`
- 测试：`test/log_sanitizer_test.dart`
- 测试：`test/diagnostic_log_exporter_test.dart`

- [ ] RED：覆盖纯 Cookie 保存、空输入保留、非空替换、删除和 Cookie 不进入 `CloudSource.toJson()`。
- [ ] RED：输入 `Cookie: a=1; b=two words; __puus=secret`，断言完整值被替换且诊断包不含片段。
- [ ] 运行目标测试，确认因现有用户名/密码门槛与正则截断而失败。
- [ ] GREEN：统一 `CloudCredential.isEmpty/mergeWith` 语义；测试连接只写内存，保存成功后才写安全存储。
- [ ] GREEN：扩展 Cookie 头脱敏到行尾/下一个头边界，保持 URL 脱敏。
- [ ] 运行目标测试，预期通过。
- [ ] 提交：`修复：保护夸克 Cookie 凭据`。

### 任务 5：夸克请求策略、解析与账号验证

**文件：**
- 新建：`lib/services/cloud/quark/quark_models.dart`
- 新建：`lib/services/cloud/quark/quark_response_parser.dart`
- 新建：`lib/services/cloud/quark/quark_request_policy.dart`
- 新建：`lib/services/cloud/quark/quark_api_client.dart`
- 测试：`test/quark_response_parser_test.dart`
- 测试：`test/quark_request_policy_test.dart`
- 测试：`test/quark_api_client_test.dart`

- [ ] RED：从账号夹具解析昵称；缺少 `data` 抛结构不兼容；401 映射 Cookie 失效，403 映射权限，429 映射限流。
- [ ] RED：断言 Cookie 仅发往已核对 API 主机或 API 返回的首始播放主机，跨主机重定向被剥离。
- [ ] 运行三个目标测试，预期因类缺失失败。
- [ ] GREEN：用 Dio 实现 10 秒连接、15 秒发送、30 秒接收超时；429/暂时性 5xx 最多三次指数退避，认证错误不重试。
- [ ] GREEN：实现 `GET pan.quark.cn/account/info` 账号验证和结构解析，禁止记录请求原文。
- [ ] 运行目标测试，预期通过。
- [ ] 提交：`功能：实现夸克安全请求与登录验证`。

### 任务 6：目录分页、选择与扫描聚合

**文件：**
- 新建：`lib/services/cloud/quark/quark_drive_client.dart`
- 修改：`lib/services/cloud/cloud_provider_registry.dart`
- 修改：`lib/services/cloud/cloud_media_indexer.dart`
- 新建：`lib/pages/cloud/quark/quark_directory_picker.dart`
- 测试：`test/quark_drive_client_test.dart`
- 测试：`test/cloud_media_indexer_test.dart`
- 测试：`test/quark_directory_picker_test.dart`

- [ ] RED：覆盖目录第一页、空目录、重复页、重复 `fid`、异常元数据和页数上限。
- [ ] RED：用视频与同名字幕夹具扫描，断言索引保存视频/字幕 ID 和路径。
- [ ] 运行目标测试，预期失败。
- [ ] GREEN：实现按 `fid` 的目录分页并规范化展示路径；重复页停止并报结构不兼容。
- [ ] GREEN：注册夸克驱动，目录选择器支持多根目录和默认转存目录。
- [ ] 运行目标测试以及 OpenList 扫描回归，预期通过。
- [ ] 提交：`功能：接入夸克目录与媒体扫描`。

### 任务 7：在线播放、字幕与单次刷新

**文件：**
- 修改：`lib/services/cloud/quark/quark_drive_client.dart`
- 修改：`lib/services/cloud/cloud_playback_resolver.dart`
- 修改：`lib/services/cloud/cloud_subtitle_cache.dart`
- 修改：`lib/pages/local/local_page.dart`（只接通通用刷新回调，不加入夸克逻辑）
- 测试：`test/quark_drive_client_test.dart`
- 测试：`test/cloud_playback_resolver_test.dart`
- 测试：`test/local_playback_request_builder_test.dart`

- [ ] RED：断言 `file/download` 使用持久化 `remoteId`，返回头含 Cookie/Referer/User-Agent。
- [ ] RED：模拟首次 401/403 后刷新一次成功；连续失败只解析两次直链。
- [ ] RED：序列化/重建索引后仍以 ID 播放，字幕也以 ID 下载。
- [ ] 运行目标测试，预期失败。
- [ ] GREEN：实现播放解析与会话级一次性刷新门，透传不可变请求头。
- [ ] GREEN：字幕缓存接收 `CloudRemoteRef`，旧路径回退保持工作。
- [ ] 运行目标测试，预期通过。
- [ ] 提交：`功能：支持夸克在线播放与字幕`。

### 任务 8：分享检查与转存任务

**文件：**
- 新建：`lib/services/cloud/quark/quark_share_transfer_service.dart`
- 新建：`lib/modules/cloud/quark/quark_share_entry.dart`
- 新建：`lib/modules/cloud/quark/quark_transfer_task.dart`
- 测试：`test/quark_share_transfer_service_test.dart`

- [ ] RED：覆盖分享 URL/提取码解析、分页展示、失效分享、错误提取码和 429。
- [ ] RED：覆盖 `saveShare()` 请求字段与成功/失败/超时/取消任务状态。
- [ ] 运行目标测试，预期因服务缺失失败。
- [ ] GREEN：实现 `inspectShare()`、`saveShare()`、`queryTask()`；短期 `stoken` 只存在服务对象内存。
- [ ] GREEN：任务轮询使用取消令牌、总时限和 500ms 起步的有上限退避。
- [ ] 运行目标测试，预期通过。
- [ ] 提交：`功能：实现夸克分享检查与转存`。

### 任务 9：幂等历史与转存后全量扫描

**文件：**
- 新建：`lib/modules/cloud/quark/quark_import_record.dart`
- 新建：`lib/repositories/quark_import_history_repository.dart`
- 新建：`lib/providers/quark_import_controller.dart`
- 测试：`test/quark_import_history_repository_test.dart`
- 测试：`test/quark_import_controller_test.dart`

- [ ] RED：断言幂等键为四字段组合，同一进行中/成功任务不能重复提交，失败/超时/取消可重试。
- [ ] RED：断言持久化 JSON 不含 `cookie`、`stoken`、URL 或 headers。
- [ ] RED：转存成功后恰好调用一次 `scanSource(sourceId)` 和媒体库刷新；失败不刷新。
- [ ] 运行目标测试，预期失败。
- [ ] GREEN：实现 Hive 历史仓库和控制器状态机。
- [ ] 运行目标测试，预期通过。
- [ ] 提交：`功能：记录夸克转存并刷新媒体库`。

### 任务 10：编辑页、导入页与路由

**文件：**
- 新建：`lib/pages/cloud/quark/quark_source_editor.dart`
- 新建：`lib/pages/cloud/quark/quark_share_import_page.dart`
- 修改：`lib/pages/settings/cloud_sources_settings.dart`
- 修改：`lib/pages/settings/settings_module.dart`
- 修改：`lib/pages/my/my_page.dart`
- 修改：`lib/pages/index_module.dart`
- 测试：`test/cloud_sources_ui_test.dart`
- 测试：`test/quark_source_editor_test.dart`
- 测试：`test/quark_share_import_page_test.dart`
- 测试：`test/navigation_config_test.dart`

- [ ] RED：断言添加菜单有 OpenList/夸克、Cookie 默认隐藏且旧值不回显、四个新路由和旧路由兼容。
- [ ] RED：只有可用夸克来源时显示分享导入入口，重复提交按钮被禁用。
- [ ] 运行目标测试，预期失败。
- [ ] GREEN：实现 Material 页面和路由，复用现有间距、按钮、加载与 SnackBar 反馈。
- [ ] GREEN：将注册器和导入控制器注入 Modular，不改播放器控件层级或动画。
- [ ] 运行目标测试，预期通过。
- [ ] 提交：`界面：增加夸克来源与分享导入`。

### 任务 11：全量回归与错误隔离

**文件：**
- 修改：仅限测试暴露的相关实现
- 测试：`test/quark_failure_isolation_test.dart`
- 测试：既有全部 `test/*.dart`

- [ ] RED：模拟夸克认证/网络/结构失败，断言本地扫描、本地播放和 OpenList 扫描仍可执行。
- [ ] GREEN：把提供商失败收敛到单来源结果，禁止全局初始化失败。
- [ ] 运行 `D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test`。
- [ ] 运行 `D:\flutter\bin\flutter.bat test --no-pub`。
- [ ] 运行 `D:\flutter\bin\flutter.bat analyze --no-pub`。
- [ ] 提交：`测试：完成夸克媒体库全量回归`。

### 任务 12：版本、Windows Release 与 MSIX 交付

**文件：**
- 修改：`pubspec.yaml`
- 修改：`RELEASE_NOTES.md`
- 修改：`lib/utils/version_history.dart`

- [ ] 选择下一个补丁版本，令 `version: x.y.z+build` 与 `msix_config.msix_version: x.y.z.0` 一致。
- [ ] 用普通用户语言更新发布说明与应用内版本历史。
- [ ] 再次依次运行格式、全量测试和分析。
- [ ] 运行 `D:\flutter\bin\flutter.bat build windows --release --no-pub`，确认本轮 `kanyingyin.exe` 和 `data/app.so` 更新时间。
- [ ] 运行 `D:\flutter\bin\dart.bat run msix:create --build-windows false`。
- [ ] 解包 MSIX，核对 `AppxManifest.xml` 的 `Identity Name=com.kanyingyin.player` 和版本。
- [ ] 使用 `Get-AuthenticodeSignature` 核对签名状态并如实记录；项目配置为不签名时不得声称已签名。
- [ ] 复制到 `$env:USERPROFILE\Desktop\看影音-x.y.z.msix`，核对大小和修改时间。
- [ ] 检查 `git status --short` 与关键 diff，明确排除 `.learnings/ERRORS.md`、`.learnings/LEARNINGS.md` 和构建产物。
- [ ] 提交：`发布：交付夸克网盘媒体库 x.y.z`。
