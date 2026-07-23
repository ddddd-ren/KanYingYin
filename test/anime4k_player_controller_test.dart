import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/anime4k_coordinator.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';

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
}
