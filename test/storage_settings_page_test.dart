import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('存储设置提供目录选择、迁移和安全清理入口', () {
    final source = File('lib/pages/settings/storage_settings_page.dart')
        .readAsStringSync();
    expect(source, contains("title: '存储'"));
    expect(source, contains("title: '应用数据目录'"));
    expect(source, contains("title: '缓存目录'"));
    expect(source, contains('FilePicker.getDirectoryPath('));
    expect(source, contains('saveMigrationRequest(previous: _resolver)'));
    expect(source, contains('重启后、打开数据库前安全迁移'));
    expect(source, contains('if (isCache)'));
    expect(source, contains('migrateDirectory('));
    expect(source, contains('原目录会保留为备份'));
    expect(source, contains('不会删除视频、索引、历史或刮削资料'));
    expect(source, contains('clearCache(_resolver.cacheRoot)'));
  });
}
