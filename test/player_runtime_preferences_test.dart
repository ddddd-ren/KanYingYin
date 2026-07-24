import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';

void main() {
  late Directory directory;
  late Box<Object?> box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('player-runtime');
    Hive.init(directory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  setUp(() => box.clear());

  test('错误类型使用安全的播放器默认值', () async {
    await box.put(SettingBoxKey.defaultPlaySpeed, 'fast');
    await box.put(SettingBoxKey.hardwareDecoder, 42);
    final preferences = PlayerRuntimePreferences(TypedSettings(box));

    final value = preferences.load();

    expect(value.playSpeed, 1.0);
    expect(value.hardwareDecoder, isNotEmpty);
    expect(value.buttonSkipTime, 80);
    expect(value.arrowKeySkipTime, 10);
  });

  test('保存跳转时间后下一次加载可见', () async {
    final preferences = PlayerRuntimePreferences(TypedSettings(box));

    await preferences.saveButtonSkipTime(45);
    await preferences.saveArrowKeySkipTime(8);

    expect(preferences.load().buttonSkipTime, 45);
    expect(preferences.load().arrowKeySkipTime, 8);
  });
}
