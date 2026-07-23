import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_import_record.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_share_import_page.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/providers/quark_import_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';

void main() {
  testWidgets('分享导入页展示链接、提取码、目标目录和操作入口', (tester) async {
    final harness = await _PageHarness.create(
      source: _source(defaultTarget: _target),
    );

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.text('导入夸克分享'), findsOneWidget);
    expect(find.text('转存到：/接收'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '更改目录'), findsOneWidget);
    expect(find.widgetWithText(TextField, '夸克分享链接'), findsOneWidget);
    expect(find.widgetWithText(TextField, '提取码（可选）'), findsOneWidget);
    expect(find.text('查看分享内容'), findsOneWidget);
  });

  testWidgets('未设置转存目录时可在导入页选择并自动加入媒体根目录', (tester) async {
    final harness = await _PageHarness.create(source: _source());

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(find.text('转存到：未设置'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '选择目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('select-target-id')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('转存到：/接收'), findsOneWidget);
    final saved = await harness.repository.getById(harness.source.id);
    expect(saved?.defaultTransferDirectory, _target);
    expect(saved?.rootPaths, contains('/接收'));
  });

  testWidgets('多个分享条目只转存和刷新一次', (tester) async {
    var refreshes = 0;
    final transfer = _PageTransferService(entries: _shareEntries);
    final harness = await _PageHarness.create(
      source: _source(defaultTarget: _target),
      transfer: transfer,
      refreshSource: (_) async => refreshes++,
    );

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await _inspectAndSelectAll(tester);
    await tester.tap(find.widgetWithText(FilledButton, '转存所选内容'));
    await tester.pumpAndSettle();

    expect(transfer.saveCalls, 1);
    expect(transfer.savedEntries, hasLength(2));
    expect(refreshes, 1);
    expect(find.text('转存完成，已扫描到媒体库'), findsOneWidget);
  });

  testWidgets('已有默认转存目录在转存前自动纳入媒体根目录', (tester) async {
    final transfer =
        _PageTransferService(entries: _shareEntries.take(1).toList());
    final harness = await _PageHarness.create(
      source: _source(defaultTarget: _target),
      transfer: transfer,
    );

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await _inspectAndSelectAll(tester);
    await tester.tap(find.widgetWithText(FilledButton, '转存所选内容'));
    await tester.pumpAndSettle();

    final saved = await harness.repository.getById(harness.source.id);
    expect(saved?.rootPaths, contains('/接收'));
    expect(transfer.saveCalls, 1);
  });

  testWidgets('转存成功但媒体库刷新失败时显示部分成功提示', (tester) async {
    final transfer = _PageTransferService(entries: _shareEntries);
    final harness = await _PageHarness.create(
      source: _source(defaultTarget: _target),
      transfer: transfer,
      refreshSource: (_) async => throw StateError('模拟刷新失败'),
    );

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await _inspectAndSelectAll(tester);
    await tester.tap(find.widgetWithText(FilledButton, '转存所选内容'));
    await tester.pumpAndSettle();

    expect(find.text('文件已转存，但媒体库刷新失败，请重试扫描'), findsOneWidget);
  });

  testWidgets('扫描统计更新后再次更改转存目录不会回写旧统计', (tester) async {
    final transfer =
        _PageTransferService(entries: _shareEntries.take(1).toList());
    final harness = await _PageHarness.create(
      source: _source(defaultTarget: _target),
      transfer: transfer,
      refreshWithRepository: (repository, sourceId) =>
          repository.updateScanSummary(
        sourceId,
        status: CloudScanStatus.completed,
        scannedAt: DateTime.utc(2026, 7, 24, 12),
        videoCount: 42,
        subtitleCount: 7,
        failureCount: 0,
      ),
    );

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await _inspectAndSelectAll(tester);
    await tester.tap(find.widgetWithText(FilledButton, '转存所选内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '更改目录'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('select-second-target-id')),
    );
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final saved = await harness.repository.getById(harness.source.id);
    expect(saved?.indexedVideoCount, 42);
    expect(saved?.matchedSubtitleCount, 7);
    expect(saved?.scanStatus, CloudScanStatus.completed);
    expect(saved?.defaultTransferDirectory, _secondTarget);
  });

  testWidgets('远程任务进行中关闭页面会等待任务结束后再释放资源', (tester) async {
    final task = Completer<QuarkTransferTask>();
    final transfer = _PageTransferService(
      entries: _shareEntries.take(1).toList(),
      pendingTask: task,
      failPendingTaskOnClose: true,
    );
    final harness = await _PageHarness.create(
      source: _source(defaultTarget: _target),
      transfer: transfer,
    );

    await tester.pumpWidget(harness.app(ownDependencies: true));
    await tester.pumpAndSettle();
    await _inspectAndSelectAll(tester);
    await tester.tap(find.widgetWithText(FilledButton, '转存所选内容'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    if (!task.isCompleted) {
      task.complete(const QuarkTransferTask(
        id: 'task-fixture',
        status: QuarkTransferTaskStatus.succeeded,
      ));
    }
    await tester.pumpAndSettle();

    final records = await harness.historyRepository.getAll();
    expect(records, hasLength(1));
    expect(records.single.status, QuarkImportStatus.succeeded);
    expect(transfer.closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _inspectAndSelectAll(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, '夸克分享链接'),
    'https://pan.quark.cn/s/share-fixture',
  );
  await tester.tap(find.text('查看分享内容'));
  await tester.pumpAndSettle();
  for (final checkbox in find.byType(CheckboxListTile).evaluate().toList()) {
    await tester.tap(find.byWidget(checkbox.widget));
  }
  await tester.pump();
}

const _target = CloudRemoteRef(id: 'target-id', path: '/接收');
const _secondTarget = CloudRemoteRef(id: 'second-target-id', path: '/另一个接收目录');

const _shareEntries = <QuarkShareEntry>[
  QuarkShareEntry(
    id: 'shared-first',
    name: '示例目录一',
    isDirectory: true,
    size: 0,
    fileToken: 'file-token-first',
  ),
  QuarkShareEntry(
    id: 'shared-second',
    name: '示例目录二',
    isDirectory: true,
    size: 0,
    fileToken: 'file-token-second',
  ),
];

CloudSource _source({CloudRemoteRef? defaultTarget}) => CloudSource(
      id: 'quark-fixture',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: const <String>['/影视'],
      rootRefs: const <CloudRemoteRef>[
        CloudRemoteRef(id: 'movies-id', path: '/影视'),
      ],
      defaultTransferDirectory: defaultTarget,
    );

class _PageHarness {
  _PageHarness({
    required this.source,
    required this.repository,
    required this.credentials,
    required this.cloudController,
    required this.transfer,
    required this.importer,
    required this.historyRepository,
  });

  final CloudSource source;
  final CloudSourceRepository repository;
  final MemoryCloudCredentialStore credentials;
  final CloudLibraryController cloudController;
  final _PageTransferService transfer;
  final QuarkImportController importer;
  final QuarkImportHistoryRepository historyRepository;

  static Future<_PageHarness> create({
    required CloudSource source,
    _PageTransferService? transfer,
    QuarkSourceRefresher? refreshSource,
    Future<void> Function(CloudSourceRepository repository, String sourceId)?
        refreshWithRepository,
  }) async {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await repository.save(source);
    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'cookie-fixture'),
    );
    final cloudController = CloudLibraryController(
      repository: repository,
      credentialStore: credentials,
      clientFactory: (_, __, ___) => _DirectoryClient(),
    );
    final actualTransfer = transfer ?? _PageTransferService();
    final historyRepository = QuarkImportHistoryRepository(
      storage: MemoryQuarkImportHistoryStorage(),
    );
    final importer = QuarkImportController(
      historyRepository: historyRepository,
      transferService: actualTransfer,
      refreshSource: refreshWithRepository != null
          ? (sourceId) => refreshWithRepository(repository, sourceId)
          : refreshSource ?? (_) async {},
    );
    return _PageHarness(
      source: source,
      repository: repository,
      credentials: credentials,
      cloudController: cloudController,
      transfer: actualTransfer,
      importer: importer,
      historyRepository: historyRepository,
    );
  }

  Widget app({bool ownDependencies = false}) => MaterialApp(
        home: QuarkShareImportPage(
          source: source,
          cloudLibraryController: cloudController,
          credentialStore: credentials,
          transferService: ownDependencies ? null : transfer,
          importController: ownDependencies ? null : importer,
          transferServiceFactory: ownDependencies ? (_) => transfer : null,
          importControllerFactory: ownDependencies ? (_) => importer : null,
        ),
      );
}

class _DirectoryClient implements CloudDriveClient {
  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async =>
      const <CloudFileEntry>[
        CloudFileEntry(
          id: 'target-id',
          remotePath: '/接收',
          name: '接收',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'second-target-id',
          remotePath: '/另一个接收目录',
          name: '另一个接收目录',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ];

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _PageTransferService implements QuarkShareTransfer {
  _PageTransferService({
    this.entries = const <QuarkShareEntry>[],
    this.pendingTask,
    this.failPendingTaskOnClose = false,
  });

  final List<QuarkShareEntry> entries;
  final Completer<QuarkTransferTask>? pendingTask;
  final bool failPendingTaskOnClose;
  int saveCalls = 0;
  List<QuarkShareEntry> savedEntries = const <QuarkShareEntry>[];
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
    final task = pendingTask;
    if (failPendingTaskOnClose && task != null && !task.isCompleted) {
      task.completeError(
        const CloudDriveException(CloudDriveErrorType.cancelled),
      );
    }
  }

  @override
  Future<QuarkShareInspection> inspectShare(
    String shareUrl, {
    String? passcode,
  }) async =>
      QuarkShareInspection(
        shareId: 'share-fixture',
        entries: entries,
      );

  @override
  Future<QuarkTransferTask> queryTask(
    String taskId, {
    int retryIndex = 0,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> saveShare({
    required String shareId,
    required List<QuarkShareEntry> entries,
    required String targetDirectoryId,
  }) async {
    saveCalls++;
    savedEntries = List<QuarkShareEntry>.from(entries);
    return 'task-fixture';
  }

  @override
  Future<QuarkTransferTask> waitForTask(
    String taskId, {
    bool Function()? isCancelled,
  }) async {
    final task = pendingTask;
    if (task != null) return task.future;
    return const QuarkTransferTask(
      id: 'task-fixture',
      status: QuarkTransferTaskStatus.succeeded,
    );
  }
}
