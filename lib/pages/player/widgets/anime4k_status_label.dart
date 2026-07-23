import 'package:flutter/material.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';

String anime4kStatusText(
  Anime4kPreference preference,
  Anime4kRuntimeState state,
) {
  final selected = switch (preference) {
    Anime4kPreference.off => '关闭',
    Anime4kPreference.efficiency => '效率档',
    Anime4kPreference.quality => '质量档',
  };
  return switch (state) {
    Anime4kRuntimeState.off => '关闭',
    Anime4kRuntimeState.waitingForSize => '$selected（等待画面尺寸）',
    Anime4kRuntimeState.notNeeded => '$selected（当前未启用）',
    Anime4kRuntimeState.loading => '$selected（正在加载）',
    Anime4kRuntimeState.efficiencyActive => '效率档（已启用）',
    Anime4kRuntimeState.qualityActive => '质量档（已启用）',
    Anime4kRuntimeState.failedDisabled => '$selected（加载失败，已关闭）',
    Anime4kRuntimeState.incompatible => '$selected（当前渲染器不兼容）',
  };
}

class Anime4kStatusLabel extends StatelessWidget {
  const Anime4kStatusLabel({
    super.key,
    required this.preference,
    required this.runtimeState,
    this.style,
  });

  final Anime4kPreference preference;
  final Anime4kRuntimeState runtimeState;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
        anime4kStatusText(preference, runtimeState),
        style: style,
      );
}
