# OpenList 与夸克扫码网盘媒体库实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为看影音增加 OpenList 与夸克扫码两类只读网盘来源，把远程视频索引到现有媒体库，并通过实时直链使用现有播放器播放。

**Architecture:** 定义与供应商无关的 `CloudDriveClient`，OpenList 和夸克分别实现认证、列表、文件信息与直链获取。远程索引独立持久化，再转换为现有媒体库可消费的统一条目；播放时通过来源 ID 重新解析直链，不持久化临时 URL。夸克非公开协议集中在可替换的协议配置中，响应结构不匹配时关闭该适配器并报告兼容错误。

**Tech Stack:** Flutter、Dart、GetX、Hive、Dio、media_kit、flutter_secure_storage、flutter_test

---

## 文件结构

- `lib/modules/cloud/`：网盘来源、文件、认证状态和远程索引模型。
- `lib/services/cloud/cloud_drive_client.dart`：供应商无关接口与错误类型。
- `lib/services/cloud/openlist/`：OpenList API 客户端与响应解析。
- `lib/services/cloud/quark/`：夸克协议配置、扫码状态机与文件客户端。
- `lib/repositories/cloud_source_repository.dart`：非敏感来源配置与远程索引。
- `lib/services/cloud/cloud_credential_store.dart`：平台安全存储中的密码、令牌和会话。
- `lib/services/cloud/cloud_media_indexer.dart`：递归扫描、增量更新、字幕关联与取消。
- `lib/services/cloud/cloud_playback_resolver.dart`：实时直链、请求头、字幕缓存和单次重试。
- `lib/providers/cloud_library_controller.dart`：配置、扫码、扫描和错误状态。
- `lib/pages/settings/cloud_sources_settings.dart`：来源管理入口。
- `lib/pages/cloud/`：添加 OpenList、夸克二维码、远程目录选择和扫描进度界面。
- 修改现有媒体库、播放器请求、历史和 TMDB 代码以消费远程条目。

### Task 1: 网盘领域模型、安全存储与统一接口

**Files:**
- Create: `lib/modules/cloud/cloud_source.dart`
- Create: `lib/modules/cloud/cloud_file_entry.dart`
- Create: `lib/modules/cloud/cloud_media_index_item.dart`
- Create: `lib/services/cloud/cloud_drive_client.dart`
- Create: `lib/services/cloud/cloud_credential_store.dart`
- Create: `lib/repositories/cloud_source_repository.dart`
- Modify: `pubspec.yaml`
- Test: `test/cloud_source_repository_test.dart`

- [ ] **Step 1: 添加安全存储依赖并写失败测试**

在 `pubspec.yaml` 添加 `flutter_secure_storage`。测试要求来源配置写入 Hive 时不包含密码、Cookie 或令牌；敏感数据只通过 `CloudCredentialStore` 以来源 ID 保存和删除。

```dart
expect(repository.exportJson(), isNot(contains('password')));
expect(repository.exportJson(), isNot(contains('cookie')));
await credentials.write(source.id, const CloudCredential(secret: 'token'));
expect((await credentials.read(source.id))?.secret, 'token');
```

- [ ] **Step 2: 运行测试确认缺少模型而失败**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\cloud_source_repository_test.dart
```

- [ ] **Step 3: 实现模型与接口**

`CloudSource` 包含 `id`、`type`、`name`、`baseUrl`、`rootPaths`、`enabled` 和扫描状态。`CloudFileEntry` 包含远程路径、名称、大小、修改时间、目录标记和稳定 ID。统一接口固定为：

```dart
abstract interface class CloudDriveClient {
  Future<void> authenticate();
  Future<List<CloudFileEntry>> listDirectory(String path);
  Future<CloudFileEntry> getFile(String path);
  Future<CloudPlaybackResource> resolvePlayback(String path);
  Future<void> close();
}
```

定义 `CloudDriveException` 的 `authentication`、`permission`、`network`、`notFound`、`incompatible` 和 `expiredLink` 类型。日志对象的 `toString` 不包含秘密字段。

- [ ] **Step 4: 实现仓库与安全存储**

非敏感配置使用现有 Hive setting box 独立键保存。`CloudCredentialStore` 包装 `FlutterSecureStorage`；测试使用内存实现。删除来源时先删凭据，再删配置。

- [ ] **Step 5: 验证并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\cloud_source_repository_test.dart
& 'D:\flutter\bin\flutter.bat' analyze lib\modules\cloud lib\services\cloud lib\repositories\cloud_source_repository.dart
git add pubspec.yaml pubspec.lock lib/modules/cloud lib/services/cloud lib/repositories/cloud_source_repository.dart test/cloud_source_repository_test.dart
git commit -m "feat: 建立网盘来源与安全凭据模型"
```

### Task 2: OpenList 客户端与来源配置

**Files:**
- Create: `lib/services/cloud/openlist/openlist_client.dart`
- Create: `lib/services/cloud/openlist/openlist_models.dart`
- Create: `lib/providers/cloud_library_controller.dart`
- Create: `lib/pages/settings/cloud_sources_settings.dart`
- Create: `lib/pages/cloud/openlist_source_editor.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Test: `test/openlist_client_test.dart`
- Test: `test/cloud_sources_ui_test.dart`

- [ ] **Step 1: 写 OpenList 失败测试**

使用 Dio 模拟适配器覆盖 `/api/auth/login`、`/api/fs/list`、`/api/fs/get`。断言登录令牌保存到凭据存储，目录解析保留路径、大小和修改时间，文件信息转换为 `CloudPlaybackResource`，且日志不包含 Authorization。

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\openlist_client_test.dart
```

- [ ] **Step 3: 实现 OpenList 客户端**

基础地址去除尾部斜杠。登录请求使用用户名与密码，后续请求通过 `Authorization` 传令牌。列表请求传 `path`、`password`、`page`、`per_page`、`refresh: false`；文件请求只在播放前调用，不长期保存 `raw_url`。

- [ ] **Step 4: 写配置界面失败测试并实现**

设置页新增“网盘数据源”。编辑器包含名称、地址、用户名、密码、自签名证书开关和“测试连接”；密码字段不回显旧值。测试连接映射为地址、证书、认证、权限和网络五类文案。

- [ ] **Step 5: 验证并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\openlist_client_test.dart test\cloud_sources_ui_test.dart
git add lib/services/cloud/openlist lib/providers/cloud_library_controller.dart lib/pages/cloud/openlist_source_editor.dart lib/pages/settings/cloud_sources_settings.dart lib/pages/settings/settings_module.dart test/openlist_client_test.dart test/cloud_sources_ui_test.dart
git commit -m "feat: 增加 OpenList 网盘来源配置"
```

### Task 3: 夸克扫码协议适配器

**Files:**
- Create: `lib/services/cloud/quark/quark_protocol_profile.dart`
- Create: `lib/services/cloud/quark/quark_qr_login_client.dart`
- Create: `lib/services/cloud/quark/quark_drive_client.dart`
- Create: `lib/pages/cloud/quark_qr_login_dialog.dart`
- Test: `test/quark_qr_login_client_test.dart`
- Test: `test/quark_drive_client_test.dart`

- [ ] **Step 1: 固定协议配置与模拟响应**

协议配置集中定义当前网页端使用的扫码令牌端点 `https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin`、扫码展示地址 `https://su.quark.cn/4_eMHBJ`、扫码状态端点 `https://uop.quark.cn/cas/ajax/getServiceTicketByQrcodeToken`、文件列表端点 `https://drive-pc.quark.cn/1/clouddrive/file/sort` 和下载信息端点 `https://drive-pc.quark.cn/1/clouddrive/file/download`。`client_id`、协议版本和必要查询参数也只存在于 `QuarkProtocolProfile`，页面或控制器不得拼接夸克 URL。扫码状态模型固定为 `loading`、`waiting`、`scanned`、`confirmed`、`expired`、`incompatible`。测试夹具只使用脱敏本地 JSON。

- [ ] **Step 2: 写扫码状态机失败测试**

模拟等待、已扫码、确认、过期和未知结构。断言轮询间隔不小于服务端建议值，关闭会话立即取消计时器，未知结构转换为 `CloudDriveException.incompatible`，Cookie 和二维码内容不出现在日志。

- [ ] **Step 3: 实现扫码客户端与兼容检查**

客户端先获取二维码令牌和展示内容，再轮询状态。确认响应必须同时通过状态码、会话字段和账号显示字段校验后才写安全存储；任何字段结构变化均返回“不兼容”，不得猜测成功。

- [ ] **Step 4: 写文件客户端失败测试并实现**

模拟分页文件列表和下载信息。文件客户端使用安全存储中的会话，解析为统一模型；401/会话无效映射为认证错误并要求重新扫码，下载直链只包装到 `CloudPlaybackResource`。

- [ ] **Step 5: 实现二维码弹窗**

弹窗显示二维码图像、倒计时和六种状态；关闭、成功或过期时停止轮询；过期仅显示手动刷新按钮。入口标注“实验性”，不提供 Cookie 导入或密码登录。

- [ ] **Step 6: 验证并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\quark_qr_login_client_test.dart test\quark_drive_client_test.dart
git add lib/services/cloud/quark lib/pages/cloud/quark_qr_login_dialog.dart test/quark_qr_login_client_test.dart test/quark_drive_client_test.dart
git commit -m "feat: 增加夸克扫码网盘适配器"
```

### Task 4: 远程扫描、字幕与索引

**Files:**
- Create: `lib/services/cloud/cloud_media_indexer.dart`
- Create: `lib/services/cloud/cloud_subtitle_cache.dart`
- Modify: `lib/repositories/cloud_source_repository.dart`
- Modify: `lib/providers/cloud_library_controller.dart`
- Test: `test/cloud_media_indexer_test.dart`

- [ ] **Step 1: 写扫描失败测试**

构造两级目录、视频、字幕、重复文件和一个失败目录。断言递归扫描继续处理成功目录，使用来源 ID 与路径隔离索引，同目录字幕按现有规则关联，取消后不覆盖旧完整索引，未变化目录不重复请求。

- [ ] **Step 2: 实现可取消增量扫描器**

扫描器使用队列而非递归调用栈，限制并发目录请求，按扩展名和现有大小阈值筛选。目录指纹由路径、子项稳定 ID、大小和修改时间组成。扫描结果先写临时集合，成功完成后替换该来源索引。

- [ ] **Step 3: 实现字幕缓存**

字幕只在播放前下载到应用缓存的 `cloud_subtitles/<sourceId>/`，文件名使用远程稳定 ID；超过 30 天未使用的缓存可清理。下载失败返回空字幕但不阻止视频播放。

- [ ] **Step 4: 验证并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\cloud_media_indexer_test.dart
git add lib/services/cloud/cloud_media_indexer.dart lib/services/cloud/cloud_subtitle_cache.dart lib/repositories/cloud_source_repository.dart lib/providers/cloud_library_controller.dart test/cloud_media_indexer_test.dart
git commit -m "feat: 扫描并索引网盘媒体"
```

### Task 5: 合并媒体库、TMDB 与来源筛选

**Files:**
- Modify: `lib/services/local_media_library_builder.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Create: `lib/services/cloud/cloud_poster_cache.dart`
- Test: `test/cloud_library_integration_test.dart`

- [ ] **Step 1: 写聚合失败测试**

输入本地条目、OpenList 条目和夸克条目，断言系列拆分规则不变、卡片保留来源 ID、可按来源筛选、离线来源保留索引但标记不可播放、同路径不同来源不去重。

- [ ] **Step 2: 实现统一媒体条目转换**

远程索引转换为媒体库输入对象，不伪造本地文件路径。分组键加入来源 ID，避免不同网盘同名目录误合并；标题识别继续复用现有解析器。

- [ ] **Step 3: 接入 TMDB 与海报缓存**

远程条目复用 TMDB 元数据流程，海报保存到 `cloud_posters/<sourceId>/<stableId>.jpg`，不调用写回视频目录的 `tmdb-poster.jpg` 逻辑。缓存失败回退网络 URL。

- [ ] **Step 4: 增加来源筛选和状态**

媒体库工具栏增加“全部、本地、各网盘来源”菜单；卡片使用来源图标与名称，离线来源禁用播放并提供刷新入口。

- [ ] **Step 5: 验证并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\cloud_library_integration_test.dart test\local_series_grouper_test.dart
git add lib/services/local_media_library_builder.dart lib/pages/local/library_sheet.dart lib/pages/local/local_controller.dart lib/services/cloud/cloud_poster_cache.dart test/cloud_library_integration_test.dart
git commit -m "feat: 将网盘视频合并到媒体库"
```

### Task 6: 实时直链播放与单次重试

**Files:**
- Create: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `lib/modules/video/local_playback_request.dart`
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Test: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写播放失败测试**

断言点击远程视频时才请求直链，请求头完整传给播放器；首个 URL 返回认证或过期错误时重新解析并只重试一次；第二次失败不循环；远程字幕下载失败仍返回可播放请求。

- [ ] **Step 2: 实现实时解析器**

解析器从来源仓库获取对应客户端，调用 `resolvePlayback`，下载匹配字幕，并构建包含 `sourceId`、`remotePath`、URL、请求头和刷新回调的播放请求。长期历史只保存来源 ID 与远程路径。

- [ ] **Step 3: 扩展播放器错误恢复**

播放器只对明确的 401、403、签名过期和 `expiredLink` 执行一次刷新。刷新时保持当前进度、播放列表、字幕偏移键和播放状态；其他解码错误沿用现有处理。

- [ ] **Step 4: 扩展字幕偏移键**

本地视频继续使用规范化文件路径；远程视频使用 `cloud:<sourceId>:<normalizedRemotePath>`，确保不同来源独立记忆。

- [ ] **Step 5: 验证并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\cloud_playback_resolver_test.dart test\local_video_controller_test.dart
git add lib/services/cloud/cloud_playback_resolver.dart lib/modules/video/local_playback_request.dart lib/pages/video/local_video_controller.dart lib/pages/player/player_controller.dart test/cloud_playback_resolver_test.dart
git commit -m "feat: 支持网盘实时直链播放"
```

### Task 7: 完整验证、版本发布和 Windows 安装包

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 更新版本与用户文案**

从 `1.3.0+10300` 升级到 `1.4.0+10400`，MSIX 使用 `1.4.0.0`，同步版本常量、发布说明和应用内更新日志。文案说明 OpenList、实验性夸克扫码、网盘媒体库和实时播放。

- [ ] **Step 2: 完整测试与静态分析**

```powershell
& 'D:\flutter\bin\flutter.bat' test
& 'D:\flutter\bin\flutter.bat' analyze
git diff --check
```

预期所有测试通过、分析无问题、无空白错误。真实账号不用于自动测试。

- [ ] **Step 3: 手动兼容验证**

使用用户自己的测试来源分别验证 OpenList 登录、目录扫描、拖动播放、字幕和直链刷新。夸克仅在扫码响应结构通过兼容检查时启用；不兼容时验证明确提示和 OpenList 不受影响。

- [ ] **Step 4: 按打包 skill 生成 MSIX**

执行 Windows Release、MSIX 生成、清单版本与签名校验，复制到桌面并核对 SHA-256。

- [ ] **Step 5: 提交发布版本**

```powershell
git add -A
git commit -m "release: 发布网盘媒体库"
git status --short
```

预期工作区干净。
