import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_share_import_page.dart';
import 'package:kanyingyin/providers/quark_import_controller.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';

void main() {
  testWidgets('分享导入页展示链接、提取码、目标目录和操作入口', (tester) async {
    final transfer = _PageTransferService();
    final importer = QuarkImportController(
      historyRepository: QuarkImportHistoryRepository(
        storage: MemoryQuarkImportHistoryStorage(),
      ),
      transferService: transfer,
      scanSource: (_) async {},
      refreshLibrary: () async {},
    );
    const source = CloudSource(
      id: 'quark-fixture',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
      defaultTransferDirectory: CloudRemoteRef(
        id: 'target-fixture',
        path: '/接收',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: QuarkShareImportPage(
        source: source,
        transferService: transfer,
        importController: importer,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('导入夸克分享'), findsOneWidget);
    expect(find.text('转存到：/接收'), findsOneWidget);
    expect(find.widgetWithText(TextField, '夸克分享链接'), findsOneWidget);
    expect(find.widgetWithText(TextField, '提取码（可选）'), findsOneWidget);
    expect(find.text('查看分享内容'), findsOneWidget);
    importer.dispose();
  });
}

class _PageTransferService implements QuarkShareTransfer {
  @override
  Future<void> close() async {}

  @override
  Future<QuarkShareInspection> inspectShare(String shareUrl,
          {String? passcode}) async =>
      const QuarkShareInspection(
        shareId: 'share-fixture',
        entries: <QuarkShareEntry>[],
      );

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
          {bool Function()? isCancelled}) async =>
      const QuarkTransferTask(
        id: 'task-fixture',
        status: QuarkTransferTaskStatus.succeeded,
      );
}
