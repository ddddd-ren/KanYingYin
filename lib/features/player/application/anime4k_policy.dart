import 'dart:math';

enum Anime4kPreference { off, efficiency, quality }

enum Anime4kRuntimeState {
  off,
  waitingForSize,
  notNeeded,
  loading,
  efficiencyActive,
  qualityActive,
  failedDisabled,
  incompatible,
}

enum Anime4kFit { contain, cover, fill }

enum Anime4kAction { clear, enableEfficiency, enableQuality }

final class Anime4kPolicyInput {
  const Anime4kPolicyInput({
    required this.preference,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.outputWidth,
    required this.outputHeight,
    required this.fit,
    required this.shaderSupported,
  });

  final Anime4kPreference preference;
  final double sourceWidth;
  final double sourceHeight;
  final double outputWidth;
  final double outputHeight;
  final Anime4kFit fit;
  final bool shaderSupported;
}

final class Anime4kDecision {
  const Anime4kDecision({
    required this.state,
    required this.action,
    required this.scale,
  });

  final Anime4kRuntimeState state;
  final Anime4kAction action;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is Anime4kDecision &&
      state == other.state &&
      action == other.action &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(state, action, scale);
}

final class Anime4kPolicy {
  const Anime4kPolicy();

  Anime4kDecision evaluate(Anime4kPolicyInput input) {
    if (input.preference == Anime4kPreference.off) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.off,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    if (!input.shaderSupported) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.incompatible,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    if (input.sourceWidth <= 0 ||
        input.sourceHeight <= 0 ||
        input.outputWidth <= 0 ||
        input.outputHeight <= 0) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.waitingForSize,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    final widthScale = input.outputWidth / input.sourceWidth;
    final heightScale = input.outputHeight / input.sourceHeight;
    final scale = switch (input.fit) {
      Anime4kFit.contain => min(widthScale, heightScale),
      Anime4kFit.cover || Anime4kFit.fill => max(widthScale, heightScale),
    };
    if (scale <= 1.05) {
      return Anime4kDecision(
        state: Anime4kRuntimeState.notNeeded,
        action: Anime4kAction.clear,
        scale: scale,
      );
    }
    return Anime4kDecision(
      state: input.preference == Anime4kPreference.efficiency
          ? Anime4kRuntimeState.efficiencyActive
          : Anime4kRuntimeState.qualityActive,
      action: input.preference == Anime4kPreference.efficiency
          ? Anime4kAction.enableEfficiency
          : Anime4kAction.enableQuality,
      scale: scale,
    );
  }
}
