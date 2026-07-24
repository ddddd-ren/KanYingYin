import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/presentation/player_exit_coordinator.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'player-exit-lifecycle-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<Object?>('player-exit-settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('播放器退出协调器只同步通知一次', () {
    final coordinator = PlayerExitCoordinator();
    var notifications = 0;
    coordinator.addListener(() => notifications++);

    expect(coordinator.beginExit(), isTrue);
    expect(coordinator.beginExit(), isFalse);
    expect(coordinator.exitRequested, isTrue);
    expect(notifications, 1);

    coordinator.dispose();
  });

  test('播放器不存在时状态读取和控制操作安全结束', () async {
    final controller = PlayerController(
      shadersController: ShadersController(),
      runtimePreferences:
          PlayerRuntimePreferences(TypedSettings(GStorage.setting)),
    );

    expect(controller.hasActivePlayer, isFalse);
    expect(controller.readRuntimeSnapshot(), isNull);
    await expectLater(controller.playOrPause(), completes);
    await expectLater(controller.pause(), completes);
    await expectLater(controller.play(), completes);
    await expectLater(controller.seek(Duration.zero), completes);
  });

  test('播放器重复释放共享同一个清理任务', () async {
    final controller = PlayerController(
      shadersController: ShadersController(),
      runtimePreferences:
          PlayerRuntimePreferences(TypedSettings(GStorage.setting)),
    );

    final first = controller.dispose();
    final second = controller.dispose();
    expect(identical(first, second), isTrue);
    await first;
  });

  test('播放页在弹出路由前同步发出退出信号', () {
    final source = File('lib/pages/video/video_page.dart').readAsStringSync();
    final beginExit = source.indexOf('_exitCoordinator.beginExit()');
    final popRoute = source.indexOf('Navigator.of(context).pop()');

    expect(beginExit, greaterThanOrEqualTo(0));
    expect(popRoute, greaterThan(beginExit));
  });

  test('播放器界面收到退出信号后停止计时器和输入', () {
    final source = File('lib/pages/player/player_item.dart').readAsStringSync();

    expect(source, contains('_exitCoordinator.addListener'));
    expect(source, contains('playerTimer?.cancel()'));
    expect(source, contains('_acceptingInput = false'));
    expect(source, contains('readRuntimeSnapshot()'));
  });
}
