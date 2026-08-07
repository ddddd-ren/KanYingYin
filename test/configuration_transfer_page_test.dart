import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/configuration_transfer/presentation/configuration_transfer_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  test('TV 文件选择错误显示明确原因', () {
    expect(
      configurationTransferErrorMessage(
        PlatformException(code: 'PickerUnavailable'),
      ),
      contains('系统文件选择器'),
    );
    expect(
      configurationTransferErrorMessage(
        PlatformException(code: 'InvalidExtension'),
      ),
      contains('.kyyconfig'),
    );
  });

  testWidgets('配置导出要求两次密码一致且成功信息不显示秘密', (tester) async {
    final fixture = await _TransferFixture.create(tmdbKey: 'tmdb-secret');
    Uint8List? saved;
    await tester.pumpWidget(MaterialApp(
      home: ConfigurationTransferPage(
        service: fixture.service,
        saveFile: (bytes, fileName) async {
          saved = bytes;
          return fileName;
        },
        openFile: () async => null,
        shareEncryptedFile: (_, __) async => ConfigurationShareOutcome.shared,
        onImported: () async {},
        capabilities: AppPlatformCapabilities.windows,
      ),
    ));

    await tester.tap(find.text('导出配置'));
    await _waitForWidget(
      tester,
      find.byKey(const ValueKey<String>('export-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('export-password')),
      'password-a',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('export-password-confirm')),
      'password-b',
    );
    await tester.tap(find.text('开始导出'));
    await tester.pump();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('export-password-confirm')),
      'password-a',
    );
    await tester.tap(find.text('开始导出'));
    await _waitForCondition(tester, () => saved != null);
    await tester.pump(const Duration(milliseconds: 500));

    expect(saved, isNotNull);
    expect(find.textContaining('导出完成'), findsOneWidget);
    expect(find.textContaining('tmdb-secret'), findsNothing);
  });

  testWidgets('配置导入先显示合并摘要，取消不写入，确认后刷新来源', (tester) async {
    final fixture = await _TransferFixture.create(tmdbKey: 'target-key');
    final encryptedFixture = (await tester.runAsync(
      () => ConfigurationArchiveCodec().encrypt(
        PortableAppConfiguration.create(
          exportedAt: DateTime.utc(2026, 8, 7),
          appVersion: '2.1.142',
          tmdbApiKey: 'imported-key',
          cloudSources: <PortableCloudSourceConfiguration>[
            PortableCloudSourceConfiguration.fromSource(
              source: const CloudSource(
                id: 'quark-import',
                type: CloudSourceType.quark,
                name: '导入夸克',
                baseUrl: 'https://pan.quark.cn',
                rootPaths: <String>[],
              ),
              credential: const CloudCredential(cookie: 'cookie-secret'),
            ),
          ],
        ),
        password: 'password-a',
      ),
    ))!;
    var refreshCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: ConfigurationTransferPage(
        service: fixture.service,
        saveFile: (_, __) async => null,
        openFile: () async => encryptedFixture,
        shareEncryptedFile: (_, __) async => ConfigurationShareOutcome.shared,
        onImported: () async => refreshCount++,
        capabilities: AppPlatformCapabilities.android,
      ),
    ));

    await _openAndInspect(tester);
    expect(find.text('新增来源：1 个'), findsOneWidget);
    expect(find.text('更新来源：0 个'), findsOneWidget);
    expect(find.text('保留来源：0 个'), findsOneWidget);
    expect(find.text('需要选择媒体目录：1 个'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(refreshCount, 0);
    expect(await fixture.repository.getAll(), isEmpty);
    expect(fixture.tmdbManager.read(), 'target-key');

    await _openAndInspect(tester);
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(refreshCount, 1);
    expect(find.textContaining('导入完成'), findsOneWidget);
    expect((await fixture.repository.getById('quark-import'))?.name, '导入夸克');
    expect(fixture.tmdbManager.read(), 'imported-key');
    expect(find.textContaining('cookie-secret'), findsNothing);
    expect(find.textContaining('imported-key'), findsNothing);
  });

  testWidgets('Android TV 导入配置先进入专用文件选择通道', (tester) async {
    final fixture = await _TransferFixture.create(tmdbKey: 'target-key');
    final encrypted = (await tester.runAsync(
      () => ConfigurationArchiveCodec().encrypt(
        PortableAppConfiguration.create(
          exportedAt: DateTime.utc(2026, 8, 7),
          appVersion: '2.1.142',
          tmdbApiKey: '',
          cloudSources: const <PortableCloudSourceConfiguration>[],
        ),
        password: 'password-a',
      ),
    ))!;
    var pickerCalls = 0;
    final directory = Directory.systemTemp.createTempSync('kyyconfig-tv-');
    final selectedFile = File('${directory.path}/import.kyyconfig')
      ..writeAsBytesSync(encrypted);
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    await tester.pumpWidget(MaterialApp(
      home: ConfigurationTransferPage(
        service: fixture.service,
        capabilities: AppPlatformCapabilities.android.copyWith(
          television: true,
        ),
        androidTvOpenFile: () async {
          pickerCalls++;
          return selectedFile.path;
        },
      ),
    ));

    await tester.tap(find.text('导入配置'));
    await _waitForWidget(tester, find.text('输入配置密码'));

    expect(pickerCalls, 1);
    expect(find.text('输入配置密码'), findsOneWidget);
    expect(selectedFile.existsSync(), isFalse);
  });
}

Future<void> _openAndInspect(WidgetTester tester) async {
  await tester.tap(find.text('导入配置'));
  await _waitForWidget(
    tester,
    find.byKey(const ValueKey<String>('import-password')),
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('import-password')),
    'password-a',
  );
  await tester.tap(find.text('检查配置'));
  await _waitForWidget(tester, find.text('确认导入配置'));
}

Future<void> _waitForWidget(WidgetTester tester, Finder finder) =>
    _waitForCondition(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition,
) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 20)) {
      throw TestFailure('等待异步配置操作超时');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _TransferFixture {
  const _TransferFixture({
    required this.repository,
    required this.tmdbManager,
    required this.service,
  });

  final CloudSourceRepository repository;
  final TmdbCredentialManager tmdbManager;
  final ConfigurationTransferService service;

  static Future<_TransferFixture> create({required String tmdbKey}) async {
    final credentialStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentialStore,
    );
    final tmdbManager = TmdbCredentialManager(
      store: MemoryTmdbCredentialStore(tmdbKey),
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {},
    );
    await tmdbManager.initialize();
    final importer = ConfigurationImporter(
      sourceRepository: repository,
      tmdbCredentialManager: tmdbManager,
    );
    return _TransferFixture(
      repository: repository,
      tmdbManager: tmdbManager,
      service: ConfigurationTransferService(
        sourceRepository: repository,
        tmdbCredentialManager: tmdbManager,
        importer: importer,
        codec: ConfigurationArchiveCodec(),
        now: () => DateTime.utc(2026, 8, 7),
        appVersion: '2.1.142',
      ),
    );
  }
}
