import 'dart:async';
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

const _efficiencyUpscaleInput = Anime4kPolicyInput(
  preference: Anime4kPreference.efficiency,
  sourceWidth: 1280,
  sourceHeight: 720,
  outputWidth: 1920,
  outputHeight: 1080,
  fit: Anime4kFit.contain,
  shaderSupported: true,
);

const _offInput = Anime4kPolicyInput(
  preference: Anime4kPreference.off,
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

  test('加载效率档期间切换质量档再关闭时完整应用流程保持串行', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final actions = <Anime4kAction>[];
    var activeExecutions = 0;
    var maxActiveExecutions = 0;
    final coordinator = Anime4kCoordinator(
      policy: const Anime4kPolicy(),
      execute: (decision) async {
        actions.add(decision.action);
        activeExecutions++;
        if (activeExecutions > maxActiveExecutions) {
          maxActiveExecutions = activeExecutions;
        }
        try {
          if (decision.action == Anime4kAction.enableEfficiency) {
            firstStarted.complete();
            await releaseFirst.future;
          }
        } finally {
          activeExecutions--;
        }
      },
    );

    final efficiency = coordinator.evaluateAndApply(_efficiencyUpscaleInput);
    await firstStarted.future;
    final quality = coordinator.evaluateAndApply(_qualityUpscaleInput);
    final clear = coordinator.evaluateAndApply(_offInput);
    await Future<void>.delayed(Duration.zero);

    expect(actions, <Anime4kAction>[Anime4kAction.enableEfficiency]);
    expect(maxActiveExecutions, 1);

    releaseFirst.complete();
    await Future.wait(<Future<Anime4kDecision>>[efficiency, quality, clear]);

    expect(actions, <Anime4kAction>[
      Anime4kAction.enableEfficiency,
      Anime4kAction.enableQuality,
      Anime4kAction.clear,
    ]);
    expect(maxActiveExecutions, 1);
  });

  test('加载中重新选择后旧请求失败不会锁住最新请求', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final firstError = StateError('old shader failed');
    final actions = <Anime4kAction>[];
    var isFirstExecution = true;
    final coordinator = Anime4kCoordinator(
      policy: const Anime4kPolicy(),
      execute: (decision) async {
        actions.add(decision.action);
        if (!isFirstExecution) return;
        isFirstExecution = false;
        firstStarted.complete();
        await releaseFirst.future;
        throw firstError;
      },
    );

    final oldRequest = coordinator.evaluateAndApply(_efficiencyUpscaleInput);
    await firstStarted.future;
    coordinator.resetFailureLock();
    final latestRequest = coordinator.evaluateAndApply(_qualityUpscaleInput);

    releaseFirst.complete();
    final oldDecision = await oldRequest;
    final latestDecision = await latestRequest;

    expect(oldDecision.state, Anime4kRuntimeState.failedDisabled);
    expect(latestDecision.state, Anime4kRuntimeState.qualityActive);
    expect(actions, <Anime4kAction>[
      Anime4kAction.enableEfficiency,
      Anime4kAction.enableQuality,
    ]);
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
