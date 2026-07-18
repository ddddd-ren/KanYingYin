import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Object?> box;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('typed-settings');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDownAll(() async {
    await box.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('通用对象列表中的字符串设置可按强类型读取', () async {
    await box.put('shortcuts', <Object?>['space', 'enter']);

    expect(
      box.getTypedList<String>('shortcuts', defaultValue: const <String>[]),
      <String>['space', 'enter'],
    );
  });
}
