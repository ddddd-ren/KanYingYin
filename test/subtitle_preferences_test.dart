import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('subtitle-preferences');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('读取非法值时回退默认并限制范围', () async {
    await box.put(SettingBoxKey.subtitleFontSize, 'bad');
    await box.put(SettingBoxKey.subtitleBorderSize, 99);
    await box.put(SettingBoxKey.subtitlePosition, 1);
    final preferences = SubtitlePreferences(storage: box);

    final style = preferences.loadStyle();
    expect(style.fontSize, SubtitleStyleSettings.defaultFontSize);
    expect(style.borderSize, SubtitleStyleSettings.defaultBorderSize);
    expect(style.position, SubtitleStyleSettings.defaultPosition);
  });

  test('保存和读取当前视频 delay，零值删除且保留其他视频', () async {
    final preferences = SubtitlePreferences(storage: box);
    await preferences.saveDelay('other', 2.5);
    await preferences.saveDelay('current', 1.24);
    expect(preferences.loadDelay('current'), 1.0);
    await preferences.saveDelay('current', 0);
    expect(preferences.loadDelay('current'), 0);
    expect(preferences.loadDelay('other'), 2.5);
  });

  test('保存并读取八项字幕样式', () async {
    final preferences = SubtitlePreferences(storage: box);
    const expected = SubtitleStyleSettings(
      fontSize: 48,
      colorValue: 0xffeeeeee,
      borderColorValue: 0xff111111,
      borderSize: 3,
      shadowEnabled: false,
      shadowOffset: 4,
      position: 80,
      forceStyle: true,
    );
    await preferences.saveStyle(expected);

    final actual = preferences.loadStyle();
    expect(actual.fontSize, expected.fontSize);
    expect(actual.colorValue, expected.colorValue);
    expect(actual.borderColorValue, expected.borderColorValue);
    expect(actual.borderSize, expected.borderSize);
    expect(actual.shadowEnabled, expected.shadowEnabled);
    expect(actual.shadowOffset, expected.shadowOffset);
    expect(actual.position, expected.position);
    expect(actual.forceStyle, expected.forceStyle);
  });

  test('读取越界或旧类型 delay 时回退零', () async {
    await box.put(SettingBoxKey.subtitleDelayByVideo, <String, Object?>{
      'too-large': 31,
      'old': '1.5',
    });
    final preferences = SubtitlePreferences(storage: box);

    expect(preferences.loadDelay('too-large'), 0);
    expect(preferences.loadDelay('old'), 0);
  });
}
