import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
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

  setUp(() async {
    await box.clear();
  });

  test('通用对象列表中的字符串设置可按强类型读取', () async {
    await box.put('shortcuts', <Object?>['space', 'enter']);

    expect(
      box.getTypedList<String>('shortcuts', defaultValue: const <String>[]),
      <String>['space', 'enter'],
    );
  });

  test('标量设置类型错误时返回默认值', () async {
    await box.put('theme', 42);

    expect(box.getTyped<String>('theme', defaultValue: 'system'), 'system');
  });

  test('null 设置返回默认值', () async {
    await box.put('theme', null);

    expect(box.getTyped<String>('theme', defaultValue: 'system'), 'system');
  });

  test('混合类型列表整体回退且不修改默认列表', () async {
    await box.put('shortcuts', <Object?>['space', 42]);
    final defaults = <String>['enter'];

    final result = box.getTypedList<String>(
      'shortcuts',
      defaultValue: defaults,
    );

    expect(result, same(defaults));
    expect(defaults, <String>['enter']);
  });

  test('null 列表返回原默认列表实例', () async {
    await box.put('shortcuts', null);
    final defaults = <String>['enter'];

    expect(
      box.getTypedList<String>('shortcuts', defaultValue: defaults),
      same(defaults),
    );
  });

  test('有效通用列表返回独立强类型列表且不修改默认列表', () async {
    await box.put('shortcuts', <Object?>['space', 'enter']);
    final defaults = <String>['fallback'];

    final result = box.getTypedList<String>(
      'shortcuts',
      defaultValue: defaults,
    );
    result.add('escape');

    expect(result, <String>['space', 'enter', 'escape']);
    expect(defaults, <String>['fallback']);
    expect(result, isNot(same(defaults)));
  });

  test('TypedSettings 对错误标量类型返回默认值', () async {
    final settings = TypedSettings(box);
    await box.put('speed', 'fast');

    expect(settings.read<double>('speed', defaultValue: 1.0), 1.0);
  });

  test('TypedSettings 写入读取和删除保持强类型边界', () async {
    final settings = TypedSettings(box);

    await settings.write<double>('speed', 1.5);
    expect(settings.read<double>('speed', defaultValue: 1.0), 1.5);
    expect(settings.readRaw('speed'), 1.5);

    await settings.delete('speed');
    expect(settings.read<double>('speed', defaultValue: 1.0), 1.0);
  });
}
