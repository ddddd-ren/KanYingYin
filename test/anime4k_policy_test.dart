import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';

void main() {
  const policy = Anime4kPolicy();

  test('关闭档始终清空着色器', () {
    expect(
      policy
          .evaluate(const Anime4kPolicyInput(
            preference: Anime4kPreference.off,
            sourceWidth: 1280,
            sourceHeight: 720,
            outputWidth: 1920,
            outputHeight: 1080,
            fit: Anime4kFit.contain,
            shaderSupported: true,
          ))
          .action,
      Anime4kAction.clear,
    );
  });

  test('尺寸未就绪时等待且不启用', () {
    final decision = policy.evaluate(const Anime4kPolicyInput(
      preference: Anime4kPreference.quality,
      sourceWidth: 0,
      sourceHeight: 0,
      outputWidth: 1920,
      outputHeight: 1080,
      fit: Anime4kFit.contain,
      shaderSupported: true,
    ));
    expect(decision.state, Anime4kRuntimeState.waitingForSize);
    expect(decision.action, Anime4kAction.clear);
  });

  test('contain 放大超过百分之五才启用效率档', () {
    Anime4kDecision decide(double width) => policy.evaluate(Anime4kPolicyInput(
          preference: Anime4kPreference.efficiency,
          sourceWidth: 1920,
          sourceHeight: 1080,
          outputWidth: width,
          outputHeight: width * 9 / 16,
          fit: Anime4kFit.contain,
          shaderSupported: true,
        ));
    expect(decide(2016).state, Anime4kRuntimeState.notNeeded);
    expect(decide(2017).action, Anime4kAction.enableEfficiency);
  });

  test('cover 和 fill 任一方向明显放大时启用', () {
    for (final fit in <Anime4kFit>[Anime4kFit.cover, Anime4kFit.fill]) {
      final decision = policy.evaluate(Anime4kPolicyInput(
        preference: Anime4kPreference.quality,
        sourceWidth: 1920,
        sourceHeight: 1080,
        outputWidth: 1280,
        outputHeight: 1200,
        fit: fit,
        shaderSupported: true,
      ));
      expect(decision.action, Anime4kAction.enableQuality, reason: fit.name);
    }
  });

  test('渲染器不支持 GLSL 时报告不兼容', () {
    final decision = policy.evaluate(const Anime4kPolicyInput(
      preference: Anime4kPreference.quality,
      sourceWidth: 1280,
      sourceHeight: 720,
      outputWidth: 1920,
      outputHeight: 1080,
      fit: Anime4kFit.contain,
      shaderSupported: false,
    ));
    expect(decision.state, Anime4kRuntimeState.incompatible);
    expect(decision.action, Anime4kAction.clear);
  });
}
