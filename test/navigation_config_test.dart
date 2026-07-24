import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/pages/settings/settings_module.dart';

void main() {
  test('navigation config drives startup page validation', () {
    expect(appNavigationDestinations.map((item) => item.label), [
      '本地媒体库',
      '网盘媒体库',
      '设置',
    ]);
    expect(appNavigationDestinations.first.path, '/local');
    expect(isValidStartupPage('/tab/popular/'), isFalse);
    expect(isValidStartupPage('/tab/cloud/'), isTrue);
    expect(isValidStartupPage('/tab/local/'), isTrue);
    final removedLegacyPath = '/tab/${'tv'}${'box'}/movie/';
    expect(isValidStartupPage(removedLegacyPath), isFalse);
    expect(navigationIndexForStartupPage('/tab/local/'), 0);
    expect(defaultStartupPage, '/tab/local/');
  });

  test('媒体识别设置具有入口、路由和分离的生产依赖注入', () {
    final myPage = File('lib/pages/my/my_page.dart').readAsStringSync();
    final settingsModule =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();
    final indexModule = File('lib/pages/index_module.dart').readAsStringSync();
    final infrastructureBindings =
        File('lib/app/bindings/infrastructure_bindings.dart')
            .readAsStringSync();
    final libraryBindings =
        File('lib/app/bindings/library_bindings.dart').readAsStringSync();
    final cloudBindings =
        File('lib/app/bindings/cloud_bindings.dart').readAsStringSync();
    final appBindings =
        File('lib/app/bindings/app_bindings.dart').readAsStringSync();

    expect(myPage, contains("'媒体识别'"));
    expect(
      myPage,
      contains("onOpenPath('/settings/media-recognition')"),
    );
    expect(settingsModule, contains('_child(r, "/media-recognition"'));
    expect(settingsModule, contains('MediaRecognitionSettingsPage('));
    expect(settingsModule, contains('verifyCloudRescanResult('));
    expect(
        settingsModule,
        contains('refreshLocalLibraryIndex(\n'
            '            throwOnFailure: true,'));
    expect(
        settingsModule,
        contains('reloadCloudLibraryIndex(\n'
            '            throwOnFailure: true,'));
    expect(
        infrastructureBindings,
        contains(
          'i.addSingleton<MediaRecognitionSettings>('
          'MediaRecognitionSettings.new)',
        ));
    expect(
      libraryBindings,
      contains('minRecognizedVideoSizeBytesProvider: () =>\n'
          '          Modular.get<MediaRecognitionSettings>().localMinSizeBytes'),
    );
    expect(
      cloudBindings,
      matches(
        RegExp(
          r'i\.addSingleton<CloudMediaIndexer>[\s\S]*?'
          r'minRecognizedVideoSizeBytesProvider:\s*\(\)\s*=>\s*'
          r'Modular\.get<MediaRecognitionSettings>\(\)\.cloudMinSizeBytes',
        ),
      ),
    );
    expect(
      cloudBindings,
      contains('mediaIndexer: Modular.get<CloudMediaIndexer>()'),
    );
    expect(
      cloudBindings,
      contains('i.addSingleton<CloudSeriesMatchRuleRepository>('),
    );
    expect(
      cloudBindings,
      contains('i.addSingleton<CloudSeriesMatchService>('),
    );
    expect(
      cloudBindings,
      matches(
        RegExp(
          r'seriesMatchRuleRepository:\s+'
          r'Modular\.get<CloudSeriesMatchRuleRepository>\(\)',
        ),
      ),
    );
    expect(
      cloudBindings,
      contains(
        'seriesMatchService: Modular.get<CloudSeriesMatchService>()',
      ),
    );
    expect(
      appBindings,
      contains('i.addSingleton<CloudSourceRootRefreshCoordinator>('),
    );
    expect(
      appBindings,
      contains('reloadCloudLibraryIndex(\n        throwOnFailure: true,'),
    );
    expect(
      appBindings,
      contains('reloadSourcesAndSnapshot()'),
    );
    expect(
      appBindings,
      contains('Modular.get<CloudLibraryController>().scanSource(sourceId)'),
    );
    expect(indexModule, contains('registerApplicationBindings('));
    expect(
      RegExp(
        r'onRootSelectionChanged:\s*Modular\.get<'
        r'CloudSourceRootRefreshCoordinator>\(\)\.refreshSource',
      ).allMatches(settingsModule),
      hasLength(4),
    );
  });

  test('网盘部分或全部扫描失败时转换为强类型异常', () {
    for (final successCount in <int>[1, 0]) {
      expect(
        () => verifyCloudRescanResult(
          successCount: successCount,
          totalCount: 2,
          errorMessage: '部分网盘媒体扫描失败',
        ),
        throwsA(
          isA<CloudLibraryRescanException>()
              .having((error) => error.successCount, '成功数', successCount)
              .having((error) => error.totalCount, '总数', 2),
        ),
      );
    }
  });
}
