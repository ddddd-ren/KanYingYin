import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/anime4k_coordinator.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:path/path.dart' as p;

const _qualityUpscaleInput = Anime4kPolicyInput(
  preference: Anime4kPreference.quality,
  sourceWidth: 1280,
  sourceHeight: 720,
  outputWidth: 1920,
  outputHeight: 1080,
  fit: Anime4kFit.contain,
  shaderSupported: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Box<Object?> settingBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'anime4k-player-controller-',
    );
    Hive.init(hiveDirectory.path);
    settingBox = await Hive.openBox<Object?>('settings');
    GStorage.setting = settingBox;
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('连续相同布局只执行一次效率档命令', () async {
    final commands = <List<String>>[];
    final coordinator = Anime4kCoordinator(
      policy: const Anime4kPolicy(),
      execute: (decision) async => commands.add(<String>[decision.action.name]),
    );
    const input = Anime4kPolicyInput(
      preference: Anime4kPreference.efficiency,
      sourceWidth: 1280,
      sourceHeight: 720,
      outputWidth: 1920,
      outputHeight: 1080,
      fit: Anime4kFit.contain,
      shaderSupported: true,
    );
    await coordinator.evaluateAndApply(input);
    await coordinator.evaluateAndApply(input);
    expect(commands, hasLength(1));
  });

  test('失败后锁定为关闭直到用户重新选择', () async {
    var calls = 0;
    final coordinator = Anime4kCoordinator(
      policy: const Anime4kPolicy(),
      execute: (_) async {
        calls++;
        throw StateError('gpu');
      },
    );
    final first = await coordinator.evaluateAndApply(_qualityUpscaleInput);
    final second = await coordinator.evaluateAndApply(_qualityUpscaleInput);
    expect(first.state, Anime4kRuntimeState.failedDisabled);
    expect(second.state, Anime4kRuntimeState.failedDisabled);
    expect(calls, 1);
    coordinator.resetFailureLock();
    await coordinator.evaluateAndApply(_qualityUpscaleInput);
    expect(calls, 2);
  });

  test('着色器目录未准备时 Anime4K 运行态安全降级', () async {
    final controller = PlayerController(
      shadersController: ShadersController(),
      runtimePreferences: PlayerRuntimePreferences(TypedSettings(settingBox)),
    );

    expect(controller.anime4kShadersAvailable, isFalse);
    await controller.setAnime4kPreference(Anime4kPreference.quality);

    expect(controller.anime4kRuntimeState, Anime4kRuntimeState.incompatible);
  });

  test('空着色器目录不构造 Anime4K 路径', () {
    expect(
      resolveAnime4kShaderPaths(
        directoryPath: null,
        action: Anime4kAction.enableQuality,
      ),
      isNull,
    );
  });

  test('有效着色器目录生成完整 Anime4K 路径列表', () {
    final directoryPath = p.join('C:\\temp', 'anime_shaders');

    final paths = resolveAnime4kShaderPaths(
      directoryPath: directoryPath,
      action: Anime4kAction.enableQuality,
    );

    expect(
      paths,
      <String>[
        for (final name in mpvAnime4KShaders) p.join(directoryPath, name),
      ],
    );
  });
}
