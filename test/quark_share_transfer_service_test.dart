import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';

void main() {
  test('解析分享链接和提取码并分页展示内容', () async {
    final api = _FakeShareApi(
      pages: <int, QuarkDirectoryPage>{
        1: _page(<QuarkFile>[
          _sharedFile('shared-a', '目录 A', token: 'token-a'),
        ], page: 1, total: 2),
        2: _page(<QuarkFile>[
          _sharedFile('shared-b', '视频 B.mkv', token: 'token-b'),
        ], page: 2, total: 2),
      },
    );
    final service = QuarkShareTransferService(api: api);

    final inspection = await service.inspectShare(
      'https://pan.quark.cn/s/share_fixture?pwd=2468',
    );

    expect(api.receivedShareId, 'share_fixture');
    expect(api.receivedPasscode, '2468');
    expect(inspection.shareId, 'share_fixture');
    expect(inspection.entries.map((entry) => entry.id),
        <String>['shared-a', 'shared-b']);
    expect(inspection.toString(), isNot(contains('stoken-fixture')));
  });

  test('拒绝非夸克分享链接并透传失效与提取码错误', () async {
    final service = QuarkShareTransferService(api: _FakeShareApi());
    await expectLater(
      service.inspectShare('https://example.invalid/s/share_fixture'),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.invalidAddress)),
    );

    final invalidCodeService = QuarkShareTransferService(
      api: _FakeShareApi(
        tokenError:
            const CloudDriveException(CloudDriveErrorType.invalidPasscode),
      ),
    );
    await expectLater(
      invalidCodeService.inspectShare(
        'https://pan.quark.cn/s/share_fixture',
        passcode: '0000',
      ),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.invalidPasscode)),
    );
  });

  test('选择内容转存只提交 ID、文件令牌和目标目录', () async {
    final api = _FakeShareApi(
      pages: <int, QuarkDirectoryPage>{
        1: _page(<QuarkFile>[
          _sharedFile('shared-a', '目录 A', token: 'token-a'),
        ], page: 1, total: 1),
      },
      saveTaskId: 'task-fixture',
    );
    final service = QuarkShareTransferService(api: api);
    final inspection = await service.inspectShare(
      'https://pan.quark.cn/s/share_fixture',
    );

    final taskId = await service.saveShare(
      shareId: inspection.shareId,
      entries: inspection.entries,
      targetDirectoryId: 'target-fixture',
    );

    expect(taskId, 'task-fixture');
    expect(api.savedFileIds, <String>['shared-a']);
    expect(api.savedFileTokens, <String>['token-a']);
    expect(api.savedTargetId, 'target-fixture');
  });

  test('任务轮询区分成功、失败、超时和取消', () async {
    final successful = _FakeShareApi(tasks: <QuarkTransferTask>[
      const QuarkTransferTask(
        id: 'task-fixture',
        status: QuarkTransferTaskStatus.pending,
      ),
      const QuarkTransferTask(
        id: 'task-fixture',
        status: QuarkTransferTaskStatus.succeeded,
        savedFileIds: <String>['saved-fixture'],
      ),
    ]);
    final successfulService = QuarkShareTransferService(
      api: successful,
      delay: (_) async {},
    );
    expect(
      (await successfulService.waitForTask('task-fixture')).status,
      QuarkTransferTaskStatus.succeeded,
    );

    final failedService = QuarkShareTransferService(
      api: _FakeShareApi(tasks: const <QuarkTransferTask>[
        QuarkTransferTask(
          id: 'task-fixture',
          status: QuarkTransferTaskStatus.failed,
        ),
      ]),
    );
    await expectLater(
      failedService.waitForTask('task-fixture'),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.taskFailed)),
    );

    final timeoutService = QuarkShareTransferService(
      api: _FakeShareApi(tasks: const <QuarkTransferTask>[
        QuarkTransferTask(
          id: 'task-fixture',
          status: QuarkTransferTaskStatus.pending,
        ),
      ], repeatLastTask: true),
      delay: (_) async {},
      maxTaskPolls: 2,
    );
    await expectLater(
      timeoutService.waitForTask('task-fixture'),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.taskTimeout)),
    );

    final cancelledService = QuarkShareTransferService(
      api: _FakeShareApi(),
    );
    await expectLater(
      cancelledService.waitForTask('task-fixture', isCancelled: () => true),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.cancelled)),
    );
  });
}

QuarkDirectoryPage _page(
  List<QuarkFile> items, {
  required int page,
  required int total,
}) =>
    QuarkDirectoryPage(items: items, page: page, size: 1, total: total);

QuarkFile _sharedFile(String id, String name, {required String token}) =>
    QuarkFile(
      id: id,
      name: name,
      isDirectory: !name.endsWith('.mkv'),
      size: 1024,
      modifiedAt: DateTime.utc(2026, 7, 19),
      category: 1,
      shareFileToken: token,
    );

class _FakeShareApi implements QuarkShareApi {
  _FakeShareApi({
    this.pages = const <int, QuarkDirectoryPage>{},
    this.tokenError,
    this.saveTaskId = 'task-fixture',
    List<QuarkTransferTask> tasks = const <QuarkTransferTask>[],
    this.repeatLastTask = false,
  }) : tasks = List<QuarkTransferTask>.from(tasks);

  final Map<int, QuarkDirectoryPage> pages;
  final Object? tokenError;
  final String saveTaskId;
  final List<QuarkTransferTask> tasks;
  final bool repeatLastTask;
  String? receivedShareId;
  String? receivedPasscode;
  List<String>? savedFileIds;
  List<String>? savedFileTokens;
  String? savedTargetId;
  QuarkTransferTask? _lastTask;

  @override
  Future<void> close() async {}

  @override
  Future<String> getShareToken({
    required String shareId,
    required String passcode,
  }) async {
    if (tokenError != null) throw tokenError!;
    receivedShareId = shareId;
    receivedPasscode = passcode;
    return 'stoken-fixture';
  }

  @override
  Future<QuarkDirectoryPage> listSharePage({
    required String shareId,
    required String shareToken,
    required String directoryId,
    required int page,
    int size = 50,
  }) async =>
      pages[page]!;

  @override
  Future<String> saveShare({
    required String shareId,
    required String shareToken,
    required List<String> fileIds,
    required List<String> fileTokens,
    required String targetDirectoryId,
  }) async {
    savedFileIds = fileIds;
    savedFileTokens = fileTokens;
    savedTargetId = targetDirectoryId;
    return saveTaskId;
  }

  @override
  Future<QuarkTransferTask> queryTask({
    required String taskId,
    required int retryIndex,
  }) async {
    if (tasks.isNotEmpty) _lastTask = tasks.removeAt(0);
    if (_lastTask != null && (repeatLastTask || tasks.isEmpty))
      return _lastTask!;
    return _lastTask!;
  }
}
