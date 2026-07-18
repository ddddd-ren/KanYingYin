import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Object?> box;

  setUp(() async {
    hiveDirectory =
        await Directory.systemTemp.createTemp('local_library_preferences_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('读取目录偏好时过滤脏值并规范化最近目录', () async {
    await box.put(SettingBoxKey.lastLocalDirectory, 42);
    await box.put(SettingBoxKey.localDefaultPath, '  D:\\Media  ');
    await box.put(SettingBoxKey.localRecentDirectories, <Object?>[
      '',
      'A',
      7,
      'A',
      ' ',
      ...List<String>.generate(12, (index) => 'P$index'),
    ]);
    final preferences = LocalLibraryPreferences(box: box);

    expect(preferences.lastLocalDirectory, '');
    expect(preferences.defaultPath, r'D:\Media');
    expect(
      preferences.recentDirectories,
      <String>['A', ...List<String>.generate(9, (index) => 'P$index')],
    );
  });

  test('写入最近目录时去除空值、重复项并限制十条', () async {
    final preferences = LocalLibraryPreferences(box: box);

    await preferences.saveLastLocalDirectory(' D:\\Last ');
    await preferences.saveDefaultPath(' D:\\Default ');
    await preferences.saveRecentDirectories(<String>[
      'A',
      '',
      'A',
      ...List<String>.generate(12, (index) => 'P$index'),
    ]);

    expect(box.get(SettingBoxKey.lastLocalDirectory), r'D:\Last');
    expect(box.get(SettingBoxKey.localDefaultPath), r'D:\Default');
    expect(
      box.get(SettingBoxKey.localRecentDirectories),
      <String>['A', ...List<String>.generate(9, (index) => 'P$index')],
    );
  });
}
