import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/pages/player/widgets/anime4k_status_label.dart';

void main() {
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
