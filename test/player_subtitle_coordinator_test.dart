import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/player_subtitle_coordinator.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';

void main() {
  late Directory directory;
  late Box<Object?> box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('subtitle-coordinator');
    Hive.init(directory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  setUp(() => box.clear());

  test('字幕延迟按媒体键保存且空键安全回退', () async {
    final coordinator = PlayerSubtitleCoordinator(
      SubtitlePreferences(storage: box),
    );

    await coordinator.saveDelay('local:D:/video.mp4', 1.5);

    expect(coordinator.loadDelay('local:D:/video.mp4'), 1.5);
    expect(coordinator.loadDelay(null), 0.0);
  });

  test('字幕样式通过协调器读写', () async {
    final coordinator = PlayerSubtitleCoordinator(
      SubtitlePreferences(storage: box),
    );
    const style = SubtitleStyleSettings(
      fontSize: 42,
      colorValue: 0xffffffff,
      borderColorValue: 0xff000000,
      borderSize: 3,
      shadowEnabled: false,
      shadowOffset: 0,
      position: 85,
      forceStyle: true,
    );

    await coordinator.saveStyle(style);

    expect(coordinator.loadStyle().fontSize, 42);
    expect(coordinator.loadStyle().forceStyle, isTrue);
  });
}
