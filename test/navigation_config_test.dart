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

    expect(myPage, contains("title: Text('媒体识别'"));
    expect(myPage,
        contains("Modular.to.pushNamed('/settings/media-recognition')"));
    expect(settingsModule, contains('r.child("/media-recognition"'));
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
        indexModule,
        contains(
          'i.addSingleton<MediaRecognitionSettings>('
          'MediaRecognitionSettings.new)',
        ));
    expect(
      indexModule,
      contains('minRecognizedVideoSizeBytesProvider: () =>\n'
          '              Modular.get<MediaRecognitionSettings>().localMinSizeBytes'),
    );
    expect(
      indexModule,
      matches(
        RegExp(
          r'i\.addSingleton<CloudMediaIndexer>[\s\S]*?'
          r'minRecognizedVideoSizeBytesProvider:\s*\(\)\s*=>\s*'
          r'Modular\.get<MediaRecognitionSettings>\(\)\.cloudMinSizeBytes',
        ),
      ),
    );
    expect(
      indexModule,
      contains('mediaIndexer: Modular.get<CloudMediaIndexer>()'),
    );
    expect(
      indexModule,
      contains('i.addSingleton<CloudSeriesMatchRuleRepository>('),
    );
    expect(indexModule, contains('i.addSingleton<CloudSeriesMatchService>('));
    expect(
      indexModule,
      matches(
        RegExp(
          r'seriesMatchRuleRepository:\s+'
          r'Modular\.get<CloudSeriesMatchRuleRepository>\(\)',
        ),
      ),
    );
    expect(
      indexModule,
      contains(
        'seriesMatchService: Modular.get<CloudSeriesMatchService>()',
      ),
    );
    expect(
      indexModule,
      contains('i.addSingleton<CloudSourceRootRefreshCoordinator>('),
    );
    expect(
      indexModule,
      contains('reloadCloudLibraryIndex(\n          throwOnFailure: true,'),
    );
    expect(
      indexModule,
      contains('reloadSourcesAndSnapshot()'),
    );
    expect(
      indexModule,
      contains('Modular.get<CloudLibraryController>().scanSource(sourceId)'),
    );
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
