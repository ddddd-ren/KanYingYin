import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/tv_remote_key_policy.dart';

void main() {
  test('控制栏隐藏时方向键执行播放区动作', () {
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Arrow Left',
        controlsVisible: false,
        controlsFocused: false,
      ),
      TvRemoteRoute.seekBackward,
    );
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Arrow Right',
        controlsVisible: false,
        controlsFocused: false,
      ),
      TvRemoteRoute.seekForward,
    );
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Arrow Up',
        controlsVisible: false,
        controlsFocused: false,
      ),
      TvRemoteRoute.volumeUp,
    );
  });

  test('控制栏显示时方向键先把焦点移入控制栏', () {
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Arrow Left',
        controlsVisible: true,
        controlsFocused: false,
      ),
      TvRemoteRoute.focusControls,
    );
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Arrow Down',
        controlsVisible: true,
        controlsFocused: true,
      ),
      TvRemoteRoute.ignored,
    );
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Enter',
        controlsVisible: true,
        controlsFocused: true,
      ),
      TvRemoteRoute.ignored,
    );
  });

  test('返回键按浮层、控制栏、页面顺序路由', () {
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Escape',
        controlsVisible: true,
        controlsFocused: true,
      ),
      TvRemoteRoute.back,
    );
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Escape',
        controlsVisible: true,
        controlsFocused: false,
      ),
      TvRemoteRoute.hideControls,
    );
    expect(
      TvRemoteKeyPolicy.routeFor(
        'Escape',
        controlsVisible: false,
        controlsFocused: false,
      ),
      TvRemoteRoute.back,
    );
  });

  test('播放器和两种控制栏实际接入 TV 路由与焦点边界', () {
    final playerItem = File(
      'lib/pages/player/player_item.dart',
    ).readAsStringSync();
    final fullPanel = File(
      'lib/pages/player/player_item_panel.dart',
    ).readAsStringSync();
    final compactPanel = File(
      'lib/pages/player/smallest_player_item_panel.dart',
    ).readAsStringSync();

    expect(playerItem, contains('TvRemoteKeyPolicy.routeFor('));
    expect(playerItem, contains('controlsVisible:'));
    expect(playerItem, contains('_tvControlsFocusNode'));
    expect(playerItem, contains('ExcludeFocus('));
    expect(playerItem, contains('_tvControlsFocusNode.dispose()'));
    expect(fullPanel, contains('FocusTraversalGroup('));
    expect(fullPanel, contains('final bool tvMode;'));
    expect(compactPanel, contains('FocusTraversalGroup('));
    expect(compactPanel, contains('final bool tvMode;'));
  });

  test('播放器选集使用共享 TV 三态表面并集中处理切集动作', () {
    final videoPage =
        File('lib/pages/video/video_page.dart').readAsStringSync();

    expect(videoPage, contains('TvEpisodeTileSurface('));
    expect(videoPage, contains('Future<void> _selectEpisode('));
    expect(videoPage, contains('current: isCurrent'));
    expect(videoPage, contains('autofocus: isCurrent'));
    expect(videoPage, contains('FocusTraversalGroup('));
    expect(videoPage, contains('MediaTechnicalBadgeResolver'));
    expect(videoPage, contains('MediaTechnicalBadgeRow'));
    expect(videoPage, contains('names: [item.title, item.url]'));
  });

  test('TV 返回键优先收回选集侧栏并保留播放器焦点', () {
    final videoPage =
        File('lib/pages/video/video_page.dart').readAsStringSync();

    expect(videoPage, contains('episodePanelVisible:'));
    expect(videoPage, contains('PlayerBackAction.closeEpisodePanel'));
    expect(videoPage, contains('closeTabBodyAnimated()'));
    expect(videoPage, contains('keyboardFocus.requestFocus()'));
  });
}
