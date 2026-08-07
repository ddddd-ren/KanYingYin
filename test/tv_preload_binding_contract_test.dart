import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('应用依赖注册包含 TV 个人预置导入服务及其现有服务适配器', () {
    final source = File(
      'lib/app/bindings/app_bindings.dart',
    ).readAsStringSync();

    expect(source, contains('i.addSingleton<TvPreloadImportService>'));
    expect(source, contains('ConfigurationTransferPreloadAdapter'));
    expect(source, contains('ScrapedMetadataTransferPreloadAdapter'));
    expect(source, contains('CloudLibraryPreloadRefreshAdapter'));
    expect(source, contains('HiveTvPreloadStateAdapter'));
  });
}
