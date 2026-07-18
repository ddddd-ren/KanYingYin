import 'dart:async';
import 'dart:io';

import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/pages/settings/media_recognition_settings.dart';
import 'package:kanyingyin/pages/settings/settings_module.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('media-settings-ui');
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<Object?>('settings-ui');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('默认显示本地与网盘媒体识别大小', (tester) async {
    final storage = _MemoryStorage();
    await _pumpPage(tester, storage: storage);

    expect(find.text('媒体识别'), findsOneWidget);
    expect(find.text('本地媒体库'), findsOneWidget);
    expect(find.text('网盘媒体库'), findsOneWidget);
    expect(find.text('800 MB'), findsOneWidget);
    expect(find.text('1 MB'), findsOneWidget);
    expect(find.text('忽略小于或等于此大小的本地视频'), findsOneWidget);
    expect(find.text('忽略小于或等于此大小的网盘视频'), findsOneWidget);
  });

  testWidgets('选择预设后保存且稍后不扫描', (tester) async {
    final storage = _MemoryStorage();
    var localScans = 0;
    await _pumpPage(
      tester,
      storage: storage,
      onRescanLocal: () async => localScans++,
    );

    await tester.tap(find.text('本地媒体库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 MB'));
    await tester.pumpAndSettle();

    expect(find.text('是否立即重新扫描'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(storage.localBytes, 10 * MediaRecognitionSettings.bytesPerMegabyte);
    expect(localScans, 0);
    expect(find.text('10 MB'), findsOneWidget);
  });

  testWidgets('快速重复点击只打开一个大小选择流程', (tester) async {
    final storage = _MemoryStorage();
    await _pumpPage(tester, storage: storage);

    final tileFinder = find.widgetWithText(SettingsTile<void>, '本地媒体库');
    final tile = tester.widget<SettingsTile<void>>(tileFinder);
    final context = tester.element(tileFinder);
    tile.onPressed!(context);
    tile.onPressed!(context);
    await tester.pumpAndSettle();

    expect(find.text('本地媒体识别大小'), findsOneWidget);
  });

  testWidgets('等待设置保存时不能开启另一个设置流程', (tester) async {
    final writeBarrier = Completer<void>();
    final storage = _MemoryStorage(writeBarrier: writeBarrier.future);
    await _pumpPage(tester, storage: storage);

    await tester.tap(find.text('本地媒体库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 MB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网盘媒体库'));
    await tester.pumpAndSettle();

    expect(find.text('网盘媒体识别大小'), findsNothing);
    expect(find.text('是否立即重新扫描'), findsNothing);

    writeBarrier.complete();
    await tester.pumpAndSettle();
    expect(find.text('是否立即重新扫描'), findsOneWidget);
  });

  testWidgets('本地立即扫描只调用本地回调', (tester) async {
    final storage = _MemoryStorage();
    var localScans = 0;
    var cloudScans = 0;
    await _pumpPage(
      tester,
      storage: storage,
      onRescanLocal: () async => localScans++,
      onRescanCloud: () async => cloudScans++,
    );

    await _choosePresetAndScan(tester, '本地媒体库', '50 MB');

    expect(localScans, 1);
    expect(cloudScans, 0);
  });

  testWidgets('网盘立即扫描只调用网盘回调', (tester) async {
    final storage = _MemoryStorage();
    var localScans = 0;
    var cloudScans = 0;
    await _pumpPage(
      tester,
      storage: storage,
      onRescanLocal: () async => localScans++,
      onRescanCloud: () async => cloudScans++,
    );

    await _choosePresetAndScan(tester, '网盘媒体库', '100 MB');

    expect(localScans, 0);
    expect(cloudScans, 1);
  });

  for (final successCount in <int>[1, 0]) {
    final failureKind = successCount == 0 ? '全部失败' : '部分失败';
    testWidgets('网盘立即扫描$failureKind时显示错误且保留设置', (tester) async {
      final storage = _MemoryStorage();
      await _pumpPage(
        tester,
        storage: storage,
        onRescanCloud: () async {
          verifyCloudRescanResult(
            successCount: successCount,
            totalCount: 2,
            errorMessage: '部分网盘媒体扫描失败',
          );
        },
      );

      await _choosePresetAndScan(tester, '网盘媒体库', '100 MB');

      expect(find.text('网盘媒体库重新扫描失败，请检查连接后重试'), findsOneWidget);
      expect(
        storage.cloudBytes,
        100 * MediaRecognitionSettings.bytesPerMegabyte,
      );
    });
  }

  testWidgets('网盘来源加载失败时显示错误提示', (tester) async {
    final storage = _MemoryStorage();
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: _FailingCloudSourceStorage(),
        credentialStore: MemoryCloudCredentialStore(),
      ),
    );
    await _pumpPage(
      tester,
      storage: storage,
      onRescanCloud: () async {
        await controller.scanAllSources();
      },
    );

    await _choosePresetAndScan(tester, '网盘媒体库', '100 MB');

    expect(find.text('网盘媒体库重新扫描失败，请检查连接后重试'), findsOneWidget);
    expect(controller.errorMessage, '网盘数据源加载失败');
  });

  testWidgets('自定义非负整数可以保存', (tester) async {
    final storage = _MemoryStorage();
    await _pumpPage(tester, storage: storage);

    await tester.tap(find.text('网盘媒体库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(storage.cloudBytes, 123 * MediaRecognitionSettings.bytesPerMegabyte);
    expect(find.text('123 MB'), findsOneWidget);
  });

  for (final invalid in ['', '-1', '1.5', 'abc']) {
    testWidgets('自定义输入“$invalid”不保存并提示非负整数', (tester) async {
      final storage = _MemoryStorage();
      await _pumpPage(tester, storage: storage);

      await tester.tap(find.text('本地媒体库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), invalid);
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('请输入非负整数'), findsOneWidget);
      expect(storage.writes, 0);
    });
  }

  testWidgets('自定义输入超过上限不保存并提示最大值', (tester) async {
    final storage = _MemoryStorage();
    await _pumpPage(tester, storage: storage);

    await tester.tap(find.text('本地媒体库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1048577');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('最大支持 1048576 MB'), findsOneWidget);
    expect(storage.writes, 0);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _MemoryStorage storage,
  Future<void> Function()? onRescanLocal,
  Future<void> Function()? onRescanCloud,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaRecognitionSettingsPage(
      settings: MediaRecognitionSettings(storage: storage),
      onRescanLocal: onRescanLocal ?? () async {},
      onRescanCloud: onRescanCloud ?? () async {},
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _choosePresetAndScan(
  WidgetTester tester,
  String target,
  String preset,
) async {
  await tester.tap(find.text(target));
  await tester.pumpAndSettle();
  await tester.tap(find.text(preset));
  await tester.pumpAndSettle();
  await tester.tap(find.text('立即扫描'));
  await tester.pumpAndSettle();
}

class _MemoryStorage implements RecognitionSettingsStorage {
  _MemoryStorage({this.writeBarrier});

  final Future<void>? writeBarrier;
  final Map<String, int> _values = <String, int>{};
  int writes = 0;

  int? get localBytes => _values['localMinRecognizedVideoSizeBytes'];
  int? get cloudBytes => _values['cloudMinRecognizedVideoSizeBytes'];

  @override
  Object? read(String key) => _values[key];

  @override
  Future<void> write(String key, int value) async {
    await writeBarrier;
    writes++;
    _values[key] = value;
  }
}

class _FailingCloudSourceStorage implements CloudSourceStorage {
  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, dynamic>>> read() async {
    throw StateError('模拟来源加载失败');
  }

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {}
}
