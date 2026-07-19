import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_import_record.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';
import 'package:kanyingyin/providers/quark_import_controller.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';

void main() {
  const entry = QuarkShareEntry(
    id: 'shared-fixture',
    name: '示例目录',
    isDirectory: true,
    size: 0,
    fileToken: 'file-token-fixture',
  );

  test('转存成功后只触发一次完整来源扫描和媒体库刷新', () async {
    var scans = 0;
    var refreshes = 0;
    final controller = QuarkImportController(
      historyRepository: QuarkImportHistoryRepository(
        storage: MemoryQuarkImportHistoryStorage(),
      ),
      transferService: _FakeTransferService(),
      scanSource: (_) async => scans++,
      refreshLibrary: () async => refreshes++,
    );

    final task = await controller.importEntry(
      sourceId: 'source-fixture',
      shareId: 'share-fixture',
      entry: entry,
      targetDirectoryId: 'target-fixture',
    );

    expect(task.status, QuarkTransferTaskStatus.succeeded);
    expect(scans, 1);
    expect(refreshes, 1);
    expect(controller.busy, isFalse);
  });

  test('相同进行中或成功转存被幂等拦截', () async {
    final repository = QuarkImportHistoryRepository(
      storage: MemoryQuarkImportHistoryStorage(),
    );
    final controller = QuarkImportController(
      historyRepository: repository,
      transferService: _FakeTransferService(),
      scanSource: (_) async {},
      refreshLibrary: () async {},
    );

    await controller.importEntry(
      sourceId: 'source-fixture',
      shareId: 'share-fixture',
      entry: entry,
      targetDirectoryId: 'target-fixture',
    );
    await expectLater(
      controller.importEntry(
        sourceId: 'source-fixture',
        shareId: 'share-fixture',
        entry: entry,
        targetDirectoryId: 'target-fixture',
      ),
      throwsA(isA<QuarkDuplicateImportException>()),
    );
  });

  test('失败、超时和取消记录状态且不刷新媒体库', () async {
    for (final type in <CloudDriveErrorType>[
      CloudDriveErrorType.taskFailed,
      CloudDriveErrorType.taskTimeout,
      CloudDriveErrorType.cancelled,
    ]) {
      var refreshed = false;
      final repository = QuarkImportHistoryRepository(
        storage: MemoryQuarkImportHistoryStorage(),
      );
      final controller = QuarkImportController(
        historyRepository: repository,
        transferService: _FakeTransferService(errorType: type),
        scanSource: (_) async {},
        refreshLibrary: () async => refreshed = true,
      );

      await expectLater(
        controller.importEntry(
          sourceId: 'source-fixture',
          shareId: 'share-fixture',
          entry: entry,
          targetDirectoryId: 'target-fixture',
        ),
        throwsA(isA<CloudDriveException>()),
      );

      final records = await repository.getAll();
      expect(
          records.single.status,
          switch (type) {
            CloudDriveErrorType.taskTimeout => QuarkImportStatus.timedOut,
            CloudDriveErrorType.cancelled => QuarkImportStatus.cancelled,
            _ => QuarkImportStatus.failed,
          });
      expect(refreshed, isFalse);
    }
  });
}

class _FakeTransferService implements QuarkShareTransfer {
  _FakeTransferService({this.errorType});
  final CloudDriveErrorType? errorType;

  @override
  Future<void> close() async {}

  @override
  Future<QuarkShareInspection> inspectShare(String shareUrl,
          {String? passcode}) async =>
      throw UnimplementedError();

  @override
  Future<QuarkTransferTask> queryTask(String taskId,
          {int retryIndex = 0}) async =>
      throw UnimplementedError();

  @override
  Future<String> saveShare({
    required String shareId,
    required List<QuarkShareEntry> entries,
    required String targetDirectoryId,
  }) async =>
      'task-fixture';

  @override
  Future<QuarkTransferTask> waitForTask(String taskId,
      {bool Function()? isCancelled}) async {
    final type = errorType;
    if (type != null) throw CloudDriveException(type);
    return const QuarkTransferTask(
      id: 'task-fixture',
      status: QuarkTransferTaskStatus.succeeded,
      savedFileIds: <String>['saved-fixture'],
    );
  }
}
