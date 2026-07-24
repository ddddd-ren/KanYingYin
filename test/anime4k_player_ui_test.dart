import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/pages/player/widgets/anime4k_status_label.dart';

void main() {
  test('超分设置明确用于动画画质增强并说明两档取舍', () {
    final source = File(
      'lib/pages/settings/super_resolution_settings.dart',
    ).readAsStringSync();

    expect(source, contains('Anime4K 动画画质增强'));
    expect(source, contains('优先保持流畅'));
    expect(source, contains('显卡负载更高'));
  });

  testWidgets('已选择质量档但无需放大时显示当前未启用', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Anime4kStatusLabel(
          preference: Anime4kPreference.quality,
          runtimeState: Anime4kRuntimeState.notNeeded,
        ),
      ),
    ));
    expect(find.text('质量档（当前未启用）'), findsOneWidget);
  });

  testWidgets('加载失败不显示已启用文案', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Anime4kStatusLabel(
          preference: Anime4kPreference.quality,
          runtimeState: Anime4kRuntimeState.failedDisabled,
        ),
      ),
    ));
    expect(find.text('质量档（加载失败，已关闭）'), findsOneWidget);
    expect(find.textContaining('已启用'), findsNothing);
  });
}
