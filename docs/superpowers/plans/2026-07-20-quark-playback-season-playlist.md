# 夸克播放与季度完整选集 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在看影音 2.1.25 中恢复夸克直连播放，并让网盘海报墙进入播放器后显示当前季度的完整真实视频列表。

**Architecture:** 夸克客户端迁移到项目播放接口，解析器在成功响应但没有转码地址时回退原文件直链，驱动层按链接类型决定安全请求头；通用播放器只增加 412 单次刷新识别。网盘资源页新增纯数据播放请求构建器，由页面确定当前季度范围，再复用现有 `LocalVideoController.openCloudPlayback`。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Dio、media_kit/libmpv、flutter_test、Windows MSIX。

---

## 文件结构

- `lib/services/cloud/quark/quark_models.dart`：定义夸克播放链接类型和“没有转码候选”异常。
- `lib/services/cloud/quark/quark_response_parser.dart`：解析项目播放候选及原文件下载地址。
- `lib/services/cloud/quark/quark_api_client.dart`：调用新项目播放接口，并在无候选时请求下载直链。
- `lib/services/cloud/quark/quark_request_policy.dart`：限定原文件 Cookie 的可信 HTTPS 主机边界。
- `lib/services/cloud/quark/quark_drive_client.dart`：根据链接类型生成播放器资源和请求头。
- `lib/services/cloud/cloud_playback_resolver.dart`：把 412 识别为可单次刷新的云链接错误。
- `lib/pages/cloud/resources/cloud_resource_playback_request.dart`：构造当前季度的完整播放请求。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：把完整请求交给测试回调或播放器控制器。
- `test/quark_api_client_test.dart`、`test/quark_response_parser_test.dart`、`test/quark_request_policy_test.dart`、`test/quark_drive_client_test.dart`：夸克接口、解析和安全边界回归。
- `test/cloud_playback_resolver_test.dart`：412 单次刷新回归。
- `test/cloud_resources_page_test.dart`：当前季度、未识别季度和单文件播放请求回归。
- `pubspec.yaml`、`README.md`、`UPDATE_DIALOG_COPY.md`、`RELEASE_NOTES.md`、`lib/core/app_version.dart`、`lib/utils/version_history.dart` 及版本测试：2.1.25 交付一致性。

### Task 1: 迁移夸克项目播放接口并增加原文件兜底

**Files:**
- Modify: `lib/services/cloud/quark/quark_models.dart`
- Modify: `lib/services/cloud/quark/quark_response_parser.dart`
- Modify: `lib/services/cloud/quark/quark_api_client.dart`
- Test: `test/quark_response_parser_test.dart`
- Test: `test/quark_api_client_test.dart`

- [ ] **Step 1: 写项目播放接口失败测试**

把 `test/quark_api_client_test.dart` 的播放用例改为断言新路径和请求体：

```dart
expect(request.uri.path, '/1/clouddrive/file/v2/play/project');
expect(request.data, <String, Object?>{
  'fid': 'fid_fixture_video',
  'resolutions': 'low,normal,high,super,2k,4k',
  'supports': 'fmp4_av,m3u8,dolby_vision',
});
```

新增队列响应测试：第一次项目播放响应的 `video_list` 为空，第二次下载响应为：

```json
{"status":200,"code":0,"data":[{"download_url":"https://download.drive.quark.cn/original"}]}
```

断言第二个请求路径为 `/1/clouddrive/file/download`、请求体为 `{'fids': ['fid_fixture_video']}`，返回链接类型为 `QuarkPlaybackLinkType.originalDownload`。

- [ ] **Step 2: 运行 API 测试并确认按预期失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\quark_api_client_test.dart
```

Expected: FAIL，旧路径仍为 `/1/clouddrive/file/v2/play`，且下载兜底类型尚不存在。

- [ ] **Step 3: 写播放候选与下载解析失败测试**

在 `test/quark_response_parser_test.dart` 新增：

```dart
test('同清晰度优先 fMP4 且缺失时允许 m3u8', () {
  final playback = parser.parsePlayback(<String, Object?>{
    'status': 200,
    'code': 0,
    'data': <String, Object?>{
      'video_list': <Object?>[
        <String, Object?>{
          'resolution': '4k',
          'format': 'm3u8',
          'video_info': <String, Object?>{
            'url': 'https://video-play.drive.quark.cn/4k.m3u8',
          },
        },
        <String, Object?>{
          'resolution': '4k',
          'format': 'fmp4_av',
          'video_info': <String, Object?>{
            'url': 'https://video-play.drive.quark.cn/4k-fmp4',
          },
        },
      ],
    },
  }, fileId: 'fid_fixture_video');

  expect(playback.uri.path, '/4k-fmp4');
  expect(playback.type, QuarkPlaybackLinkType.transcode);
});

test('没有转码候选时抛出专用异常且下载响应生成原文件链接', () {
  expect(
    () => parser.parsePlayback(<String, Object?>{
      'status': 200,
      'code': 0,
      'data': <String, Object?>{'video_list': <Object?>[]},
    }, fileId: 'fid_fixture_video'),
    throwsA(isA<QuarkNoTranscodingLinkException>()),
  );

  final download = parser.parseDownload(<String, Object?>{
    'status': 200,
    'code': 0,
    'data': <Object?>[
      <String, Object?>{
        'download_url': 'https://download.drive.quark.cn/original',
      },
    ],
  }, fileId: 'fid_fixture_video');
  expect(download.type, QuarkPlaybackLinkType.originalDownload);
});
```

同时把现有“播放响应没有可用地址时明确报接口不兼容”用例改为断言 `QuarkNoTranscodingLinkException`，确保只有“无候选”进入下载兜底，其他结构错误仍保持 `CloudDriveErrorType.incompatible`。

- [ ] **Step 4: 运行解析器测试并确认按预期失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\quark_response_parser_test.dart
```

Expected: 编译或断言失败，因为播放类型、专用异常和下载解析尚未实现。

- [ ] **Step 5: 实现最小播放模型**

在 `quark_models.dart` 增加：

```dart
enum QuarkPlaybackLinkType { transcode, originalDownload }

class QuarkNoTranscodingLinkException implements Exception {
  const QuarkNoTranscodingLinkException();
}

class QuarkPlaybackLink {
  const QuarkPlaybackLink({
    required this.fileId,
    required this.uri,
    this.type = QuarkPlaybackLinkType.transcode,
  });

  final String fileId;
  final Uri uri;
  final QuarkPlaybackLinkType type;
}
```

- [ ] **Step 6: 实现项目播放候选和下载解析**

在 `quark_response_parser.dart`：

```dart
if (fileId.isEmpty) throw _incompatible();
if (rawVideos is! List) throw const QuarkNoTranscodingLinkException();
```

选择候选时先比较 `_resolutionRank`，同分再比较：

```dart
static int _formatRank(
  Map<String, Object?> video,
  Map<String, Object?> info,
  Uri uri,
) {
  final format = <Object?>[
    video['format'],
    video['support'],
    info['format'],
    info['type'],
  ].whereType<String>().join(' ').toLowerCase();
  if (format.contains('fmp4')) return 2;
  if (format.contains('m3u8') ||
      uri.path.toLowerCase().endsWith('.m3u8')) {
    return 1;
  }
  return 0;
}
```

无有效 URI 时抛出 `QuarkNoTranscodingLinkException`。新增 `parseDownload`，只接受 `data` 列表首个有效 HTTPS `download_url`，并返回 `QuarkPlaybackLinkType.originalDownload`；结构无效时仍抛 `CloudDriveErrorType.incompatible`。

- [ ] **Step 7: 实现新接口和受控兜底**

在 `quark_api_client.dart` 定义：

```dart
static final Uri _playbackUri = Uri.https(
  'drive.quark.cn',
  '/1/clouddrive/file/v2/play/project',
);
static final Uri _downloadUri =
    Uri.https('drive.quark.cn', '/1/clouddrive/file/download');
```

`resolvePlayback` 先请求项目播放接口；只捕获 `QuarkNoTranscodingLinkException`，随后 POST 下载接口：

```dart
try {
  return _parser.parsePlayback(json, fileId: fileId);
} on QuarkNoTranscodingLinkException {
  final downloadJson = await _request(
    'POST',
    _downloadUri,
    queryParameters: const <String, Object?>{'pr': 'ucpro', 'fr': 'pc'},
    data: <String, Object?>{
      'fids': <String>[fileId],
    },
  );
  return _parser.parseDownload(downloadJson, fileId: fileId);
}
```

业务错误、鉴权错误、限流和网络异常不能进入此 catch。

- [ ] **Step 8: 运行定向测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\quark_api_client_test.dart test\quark_response_parser_test.dart
```

Expected: All tests passed。

- [ ] **Step 9: 提交接口迁移**

```powershell
git add lib/services/cloud/quark/quark_models.dart lib/services/cloud/quark/quark_response_parser.dart lib/services/cloud/quark/quark_api_client.dart test/quark_api_client_test.dart test/quark_response_parser_test.dart
git commit -m "迁移夸克项目播放接口"
```

### Task 2: 限定原文件直链请求头安全边界

**Files:**
- Modify: `lib/services/cloud/quark/quark_request_policy.dart`
- Modify: `lib/services/cloud/quark/quark_drive_client.dart`
- Test: `test/quark_request_policy_test.dart`
- Test: `test/quark_drive_client_test.dart`

- [ ] **Step 1: 写可信主机与请求头失败测试**

在 `quark_request_policy_test.dart` 新增：

```dart
test('原文件请求头只允许夸克 HTTPS 下载主机', () {
  final trusted = policy.originalDownloadHeadersFor(
    Uri.parse('https://download.drive.quark.cn/file'),
    cookie: cookie,
  );
  expect(trusted, <String, String>{
    'Cookie': cookie,
    'Referer': 'https://pan.quark.cn',
    'User-Agent': QuarkRequestPolicy.userAgent,
  });
  for (final uri in <Uri>[
    Uri.parse('http://download.drive.quark.cn/file'),
    Uri.parse('https://evilquark.cn/file'),
    Uri.parse('https://drive.quark.cn.example.com/file'),
  ]) {
    expect(policy.isTrustedOriginalDownloadUri(uri), isFalse);
    expect(
      policy.originalDownloadHeadersFor(uri, cookie: cookie),
      isEmpty,
    );
  }
});
```

- [ ] **Step 2: 写驱动按链接类型分流失败测试**

保留现有转码空请求头测试，并新增原文件链接测试，断言受信任地址包含 Cookie、Referer、User-Agent，不包含 `Accept` 和 `Content-Type`。再新增恶意相似域名链接，断言 `resolvePlayback` 抛 `CloudDriveErrorType.incompatible`。

- [ ] **Step 3: 运行测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\quark_request_policy_test.dart test\quark_drive_client_test.dart
```

Expected: 编译或断言失败，因为原文件策略和类型分流尚未实现。

- [ ] **Step 4: 实现可信原文件策略**

在 `QuarkRequestPolicy` 增加：

```dart
bool isTrustedOriginalDownloadUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'drive.quark.cn' || host.endsWith('.drive.quark.cn');
}

Map<String, String> originalDownloadHeadersFor(
  Uri uri, {
  required String cookie,
}) {
  if (!isTrustedOriginalDownloadUri(uri)) {
    return const <String, String>{};
  }
  return Map<String, String>.unmodifiable(<String, String>{
    'Cookie': cookie,
    'Referer': 'https://pan.quark.cn',
    'User-Agent': userAgent,
  });
}
```

- [ ] **Step 5: 实现驱动链接类型分流**

恢复 `QuarkDriveClient` 的 `QuarkRequestPolicy` 注入。`resolvePlayback` 中：

```dart
final headers = switch (playback.type) {
  QuarkPlaybackLinkType.transcode => const <String, String>{},
  QuarkPlaybackLinkType.originalDownload =>
    _requestPolicy.originalDownloadHeadersFor(
      playback.uri,
      cookie: cookie,
    ),
};
if (playback.type == QuarkPlaybackLinkType.originalDownload &&
    headers.isEmpty) {
  throw const CloudDriveException(CloudDriveErrorType.incompatible);
}
```

返回资源继续使用 `PlaybackNetworkRoute.direct`。

- [ ] **Step 6: 运行定向测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\quark_request_policy_test.dart test\quark_drive_client_test.dart
```

Expected: All tests passed。

- [ ] **Step 7: 提交请求头安全边界**

```powershell
git add lib/services/cloud/quark/quark_request_policy.dart lib/services/cloud/quark/quark_drive_client.dart test/quark_request_policy_test.dart test/quark_drive_client_test.dart
git commit -m "增加夸克原文件播放兜底"
```

### Task 3: 明确处理 CDN 412 单次刷新

**Files:**
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Test: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写 412 刷新失败测试**

在“只对明确鉴权、权限或签名过期错误刷新”用例增加：

```dart
expect(
  shouldRefreshCloudLink(const CloudPlaybackHttpException(412)),
  isTrue,
);
expect(shouldRefreshCloudLink('HTTP error 412 Precondition Failed'), isTrue);
expect(shouldRefreshCloudLink('status code 412'), isTrue);
```

在刷新守卫用例增加：

```dart
final guard = CloudLinkRefreshGuard();
expect(guard.tryAcquire('HTTP error 412 Precondition Failed'), isTrue);
expect(guard.tryAcquire('HTTP error 412 Precondition Failed'), isFalse);
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart
```

Expected: 412 的显式状态断言失败。

- [ ] **Step 3: 扩展刷新分类器**

把 HTTP 状态匹配从 `401|403` 扩展为 `401|403|412`，并让 `CloudPlaybackHttpException` 同样接受 412。保留现有 `CloudLinkRefreshGuard` 单次限制、进度合并、字幕保留和暂停状态逻辑，不修改刷新次数。

- [ ] **Step 4: 运行测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart
```

Expected: All tests passed。

- [ ] **Step 5: 提交 412 刷新识别**

```powershell
git add lib/services/cloud/cloud_playback_resolver.dart test/cloud_playback_resolver_test.dart
git commit -m "支持夸克播放地址四一二刷新"
```

### Task 4: 从网盘海报墙传递当前季度完整播放列表

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resource_playback_request.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 把页面测试回调升级为播放请求并写失败断言**

在 `cloud_resources_page_test.dart` 将单目标变量改为：

```dart
CloudResourcePlaybackRequest? playbackRequest;
```

页面注入改为：

```dart
onPlayRequest: (request) => playbackRequest = request,
```

在包含 S01E01、S01E02、S02E01 的现有海报墙用例中，点击 S01E02 后断言：

```dart
expect(playbackRequest?.seriesTitle, 'Show');
expect(
  playbackRequest?.targets.map((target) => target.remoteId),
  <String>['episode-1', 'episode-2'],
);
expect(
  playbackRequest?.targets.map((target) => target.remoteId),
  isNot(contains('episode-s2')),
);
expect(
  playbackRequest?.selectedStableId,
  playbackRequest?.targets.last.stableId,
);
expect(playbackRequest?.targets.last.subtitleRemoteId, 'subtitle-2');
```

更新单文件测试，断言 `targets` 长度为 1。更新未识别季度多视频测试，断言所有视频都进入请求。

- [ ] **Step 2: 运行页面测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart
```

Expected: 编译失败，因为 `CloudResourcePlaybackRequest` 和 `onPlayRequest` 尚未实现。

- [ ] **Step 3: 创建纯数据播放请求构建器**

新建 `cloud_resource_playback_request.dart`：

```dart
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

typedef CloudResourceSubtitleResolver = CloudRemoteRef? Function(
  CloudFileEntry video,
);

class CloudResourcePlaybackRequest {
  CloudResourcePlaybackRequest({
    required this.seriesTitle,
    required List<CloudPlaybackTarget> targets,
    required this.selectedStableId,
  }) : targets = List<CloudPlaybackTarget>.unmodifiable(targets);

  final String seriesTitle;
  final List<CloudPlaybackTarget> targets;
  final String selectedStableId;
}

CloudResourcePlaybackRequest buildCloudResourcePlaybackRequest({
  required String sourceId,
  required CloudResourceMediaGroup group,
  required CloudFileEntry selected,
  required CloudResourceSubtitleResolver subtitleFor,
}) {
  List<CloudFileEntry>? seasonVideos;
  for (final season in group.seasons) {
    if (season.videos.any((video) => _sameEntry(video, selected))) {
      seasonVideos = season.videos;
      break;
    }
  }
  final videos = seasonVideos ?? group.videos;
  final targets = videos.map((video) {
    final subtitle = subtitleFor(video);
    return CloudPlaybackTarget(
      sourceId: sourceId,
      remoteId: video.id,
      remotePath: video.remotePath,
      stableId: '$sourceId:${video.id}:${video.remotePath}',
      title: video.name,
      subtitleRemoteId: subtitle?.id,
      subtitleRemotePath: subtitle?.path,
    );
  }).toList(growable: false);
  final selectedTarget = targets.where(
    (target) =>
        target.remoteId == selected.id &&
        target.remotePath == selected.remotePath,
  );
  if (selectedTarget.length != 1) {
    throw ArgumentError('选中的网盘视频不在播放列表中');
  }
  return CloudResourcePlaybackRequest(
    seriesTitle: group.displayName,
    targets: targets,
    selectedStableId: selectedTarget.single.stableId,
  );
}

bool _sameEntry(CloudFileEntry first, CloudFileEntry second) =>
    first.id == second.id && first.remotePath == second.remotePath;
```

- [ ] **Step 4: 页面统一使用完整播放请求**

在 `CloudResourcesPage`：

```dart
final FutureOr<void> Function(CloudResourcePlaybackRequest request)?
    onPlayRequest;
```

把 `_play(CloudFileEntry entry)` 改为 `_play(CloudResourceMediaGroup group, CloudFileEntry entry)`，调用构建器。测试回调收到完整请求；生产路径调用：

```dart
await Modular.get<LocalVideoController>().openCloudPlayback(
  seriesTitle: request.seriesTitle,
  targets: request.targets,
  selectedStableId: request.selectedStableId,
  resolver: _playbackResolver.resolve,
);
```

`_openGroup` 的单文件和弹窗选择路径都必须把同一个 `group` 传给 `_play`。删除旧的单目标 `onPlayTarget` 字段与代码。

- [ ] **Step 5: 运行页面与播放控制器测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart test\cloud_playback_resolver_test.dart
```

Expected: All tests passed；第一季请求只含 S01E01、S01E02，单文件仍为一项。

- [ ] **Step 6: 提交季度完整选集**

```powershell
git add lib/pages/cloud/resources/cloud_resource_playback_request.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "修复网盘播放器季度选集"
```

### Task 5: 同步 2.1.25 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 写 2.1.25 版本历史失败测试**

在 `version_history_current_test.dart` 新增：

```dart
test('二点一二十五说明夸克播放和季度完整选集', () {
  final entries = versionHistoryForCurrent('2.1.25');
  expect(entries, hasLength(1));
  final changes = entries.single.changes.join('\n');
  expect(changes, contains('夸克'));
  expect(changes, contains('播放'));
  expect(changes, contains('当前季度'));
  expect(changes, contains('完整选集'));
  expect(changes, contains('不会修改网盘文件'));
  expect(entries.single.isPrerelease, isTrue);
});
```

- [ ] **Step 2: 运行版本测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\version_history_current_test.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: 2.1.25 历史不存在，当前版本仍为 2.1.24。

- [ ] **Step 3: 更新全部版本来源**

统一修改：

```text
pubspec version: 2.1.25+20125
msix_version: 2.1.25.0
AppVersion.current: 2.1.25
README 当前版本: 2.1.25
version_consistency expectedVersion: 2.1.25
version_consistency expectedBuildNumber: 20125
identity expected currentVersion: 2.1.25
```

`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 和 `version_history.dart` 使用一致的普通用户文案：

```text
- 修复夸克网盘视频持续加载并提示播放地址不可用的问题，改用当前夸克播放接口并在转码不可用时安全回退原文件地址。
- 从网盘海报墙播放剧集时，播放器现在显示当前季度的完整真实选集，并准确定位用户点击的集数。
- 本次不会修改网盘文件、目录、远程 ID、本地视频或 TMDB 信息；应用启动、本地媒体库和 OpenList 来源保持原有行为。
```

- [ ] **Step 4: 运行版本测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\version_history_current_test.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: All tests passed。

- [ ] **Step 5: 提交版本文案**

```powershell
git add pubspec.yaml lib/core/app_version.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "更新二点一二十五测试版"
```

### Task 6: 全量验证并交付签名 MSIX

**Files:**
- Verify: all modified source and test files
- Generate only: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver only: `C:/Users/asus/Desktop/看影音-2.1.25.msix`

- [ ] **Step 1: 格式化并检查差异**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\services\cloud\quark\quark_models.dart lib\services\cloud\quark\quark_response_parser.dart lib\services\cloud\quark\quark_api_client.dart lib\services\cloud\quark\quark_request_policy.dart lib\services\cloud\quark\quark_drive_client.dart lib\services\cloud\cloud_playback_resolver.dart lib\pages\cloud\resources\cloud_resource_playback_request.dart lib\pages\cloud\resources\cloud_resources_page.dart lib\core\app_version.dart lib\utils\version_history.dart test\quark_api_client_test.dart test\quark_response_parser_test.dart test\quark_request_policy_test.dart test\quark_drive_client_test.dart test\cloud_playback_resolver_test.dart test\cloud_resources_page_test.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart
git diff --check
git status --short
```

Expected: 格式化完成，`git diff --check` 无输出，只存在本轮相关改动或已提交记录。

- [ ] **Step 2: 运行全部测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test
```

Expected: `All tests passed!`，零失败。

- [ ] **Step 3: 运行静态分析**

Run:

```powershell
D:\flutter\bin\flutter.bat analyze
```

Expected: `No issues found!`。

- [ ] **Step 4: 构建本轮 Windows Release**

Run:

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
Get-Item -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.exe','build\windows\x64\runner\Release\data\app.so' | Select-Object FullName,Length,LastWriteTime
```

Expected: 构建成功，EXE 和 `app.so` 时间来自本轮。

- [ ] **Step 5: 使用本机证书生成签名 MSIX**

仅在封装期间用 `apply_patch` 把 `pubspec.yaml` 的 `sign_msix: false` 临时改为 `true`。密码只在当前 PowerShell 进程内解密：

```powershell
$secure = Import-Clixml -LiteralPath "$env:USERPROFILE\.kanyingyin\signing\certificate-password.clixml"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  D:\flutter\bin\dart.bat run msix:create --build-windows false --sign-msix true --certificate-path "$env:USERPROFILE\.kanyingyin\signing\certificate.pfx" --certificate-password $plainPassword
} finally {
  $plainPassword = $null
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
```

打包完成后立即用 `apply_patch` 恢复 `sign_msix: false`，并用 `git diff` 确认仓库契约未变化。

- [ ] **Step 6: 验证并复制安装包**

复制为：

```powershell
Copy-Item -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.msix' -Destination 'C:\Users\asus\Desktop\看影音-2.1.25.msix' -Force
```

解包到新的 `kanyingyin-msix-<GUID>` 临时目录，只读取 `AppxManifest.xml`，必须确认：

```text
Identity Name = com.kanyingyin.player
Publisher = CN=KanYingYin
Version = 2.1.25.0
ProcessorArchitecture = x64
AppxSignature.p7x = 存在
Get-AuthenticodeSignature = Valid
源包 SHA-256 = 桌面包 SHA-256
```

- [ ] **Step 7: 最终状态检查**

Run:

```powershell
git status --short
git diff --check
git log -8 --oneline
Get-AuthenticodeSignature -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.25.msix'
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.25.msix'
```

Expected: 工作树干净、签名 `Valid`、安装包哈希已记录。若格式化或最终检查产生必要改动，只暂存本轮相关文件并提交简洁中文提交信息。
