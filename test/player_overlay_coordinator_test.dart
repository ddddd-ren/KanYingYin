import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/player_overlay_coordinator.dart';

void main() {
  test('浮层互斥并支持切换', () {
    final c = PlayerOverlayCoordinator();
    expect(c.visible, PlayerOverlay.none);
    c.openSubtitleSettings();
    expect(c.visible, PlayerOverlay.subtitleSettings);
    c.open(PlayerOverlay.videoInfo);
    expect(c.visible, PlayerOverlay.videoInfo);
    c.toggle(PlayerOverlay.videoInfo);
    expect(c.visible, PlayerOverlay.none);
    c.dispose();
  });

  test('视频信息浮层提供独立公开方法', () {
    final c = PlayerOverlayCoordinator();
    c.openVideoInfo();
    expect(c.visible, PlayerOverlay.videoInfo);
    c.toggleVideoInfo();
    expect(c.visible, PlayerOverlay.none);
    c.openVideoInfo();
    c.closeVideoInfo();
    expect(c.visible, PlayerOverlay.none);
    c.dispose();
  });

  test('字幕设置打开时阻止播放器滚轮调节音量', () {
    final c = PlayerOverlayCoordinator();
    expect(c.blocksPlayerMouseWheelVolume, isFalse);

    c.openSubtitleSettings();
    expect(c.blocksPlayerMouseWheelVolume, isTrue);

    c.closeSubtitleSettings();
    expect(c.blocksPlayerMouseWheelVolume, isFalse);

    c.openVideoInfo();
    expect(c.blocksPlayerMouseWheelVolume, isFalse);
    c.dispose();
  });

  test('dispose 后不再通知', () {
    final c = PlayerOverlayCoordinator();
    var count = 0;
    c.addListener(() => count++);
    c.dispose();
    c.openSubtitleSettings();
    expect(count, 0);
  });

  test('PlayerItem 实际使用浮层协调器', () {
    final source = File('lib/pages/player/player_item.dart').readAsStringSync();
    expect(source, contains('PlayerOverlayCoordinator'));
    expect(source, contains('_overlayCoordinator.openSubtitleSettings()'));
    expect(source, contains('PlayerOverlayPresenter'));
    expect(source, contains('_overlayCoordinator.openVideoInfo()'));
    expect(
      source,
      contains('_overlayCoordinator.blocksPlayerMouseWheelVolume'),
    );
    expect(source, isNot(contains('showModalBottomSheet<void>')));
  });

  test('浮层协调器不依赖播放器控制器和服务层', () {
    final source = File(
      'lib/features/player/presentation/player_overlay_coordinator.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('pages/')));
    expect(source, isNot(contains('player_controller')));
    expect(source, isNot(contains('flutter_modular')));
    expect(source, isNot(contains('services/')));
    expect(source, isNot(contains('repositories/')));
  });

  testWidgets('打开视频信息状态后显示 BottomSheet', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    expect(find.text('视频详情'), findsOneWidget);
    c.dispose();
  });

  testWidgets('打开字幕设置时自动关闭视频信息 BottomSheet', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    c.openSubtitleSettings();
    await tester.pumpAndSettle();
    expect(find.text('视频详情'), findsNothing);
    expect(c.visible, PlayerOverlay.subtitleSettings);
    c.dispose();
  });

  testWidgets('用户关闭 BottomSheet 后状态同步为 none', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('视频详情'))).pop();
    await tester.pumpAndSettle();
    expect(c.visible, PlayerOverlay.none);
    c.dispose();
  });

  testWidgets('presenter dispose 时 BottomSheet future 安全完成', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  testWidgets('旧关闭动画完成前重新打开视频信息保留新请求', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    c.openSubtitleSettings();
    await tester.pump();
    c.openVideoInfo();
    await tester.pumpAndSettle();
    expect(find.text('视频详情'), findsOneWidget);
    expect(c.visible, PlayerOverlay.videoInfo);
    c.dispose();
  });

  testWidgets('切换 coordinator 后旧请求不写入新 coordinator', (tester) async {
    final oldCoordinator = PlayerOverlayCoordinator()..openVideoInfo();
    final newCoordinator = PlayerOverlayCoordinator()..openVideoInfo();
    await tester.pumpWidget(_presenterHost(oldCoordinator, label: '旧视频详情'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_presenterHost(newCoordinator, label: '新视频详情'));
    await tester.pumpAndSettle();
    expect(find.text('旧视频详情'), findsNothing);
    expect(find.text('新视频详情'), findsOneWidget);
    expect(newCoordinator.visible, PlayerOverlay.videoInfo);
    oldCoordinator.dispose();
    newCoordinator.dispose();
  });

  testWidgets('关闭自有 sheet 不会误关上层 Dialog', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
      context: tester.element(find.text('播放器')),
      builder: (_) => const AlertDialog(content: Text('上层对话框')),
    ));
    await tester.pumpAndSettle();
    c.openSubtitleSettings();
    await tester.pumpAndSettle();
    expect(find.text('上层对话框'), findsOneWidget);
    expect(find.text('视频详情'), findsNothing);
    expect(c.visible, PlayerOverlay.subtitleSettings);
    Navigator.of(tester.element(find.text('上层对话框'))).pop();
    await tester.pumpAndSettle();
    c.dispose();
  });
}

Widget _presenterHost(
  PlayerOverlayCoordinator coordinator, {
  String label = '视频详情',
}) {
  return MaterialApp(
    home: Scaffold(
      body: PlayerOverlayPresenter(
        key: const ValueKey('presenter'),
        coordinator: coordinator,
        videoInfoBuilder: (_) => Text(label),
        child: const Text('播放器'),
      ),
    ),
  );
}
