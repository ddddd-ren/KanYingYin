import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/player_shortcut_handler.dart';

void main() {
  test('按下、重复、抬起分别分发并返回消费状态', () async {
    final actions = <PlayerShortcutAction>[];
    final handler = PlayerShortcutHandler(
      shortcuts: const {
        'forward': ['Arrow Right'],
        'playorpause': [' ']
      },
      dispatch: (action) => actions.add(action),
    );
    expect(handler.handleKey('Arrow Right', PlayerShortcutPhase.down), isTrue);
    expect(
        handler.handleKey('Arrow Right', PlayerShortcutPhase.repeat), isTrue);
    expect(handler.handleKey('Arrow Right', PlayerShortcutPhase.up), isTrue);
    expect(actions, [
      PlayerShortcutAction.forward,
      PlayerShortcutAction.forwardRepeat,
      PlayerShortcutAction.forwardUp
    ]);
  });

  test('未知键和非法映射安全忽略', () {
    final handler = PlayerShortcutHandler.fromConfig(shortcuts: const {
      'unknown': ['X'],
      'bad': null,
      'forward': <Object?>['', 42],
    }, dispatch: (_) {});
    expect(handler.handleKey('X', PlayerShortcutPhase.down), isFalse);
    expect(handler.handleKey('', PlayerShortcutPhase.down), isFalse);
    expect(handler.handleKey('42', PlayerShortcutPhase.down), isFalse);
    final result = handler.dispatchKey('missing', PlayerShortcutPhase.down);
    expect(result.consumed, isFalse);
    expect(result.action, isNull);
    expect(result.phase, PlayerShortcutPhase.down);
  });

  test('配置解析只保留有效的非空字符串键位', () {
    final actions = <PlayerShortcutAction>[];
    final handler = PlayerShortcutHandler.fromConfig(
      shortcuts: const {
        'forward': <Object?>['Arrow Right', '', 42],
      },
      dispatch: actions.add,
    );
    expect(
      handler.handleKey('Arrow Right', PlayerShortcutPhase.down),
      isTrue,
    );
    expect(handler.handleKey('', PlayerShortcutPhase.down), isFalse);
    expect(actions, [PlayerShortcutAction.forward]);
  });

  test('全部快捷键动作映射保持一致', () {
    const expected = <String, PlayerShortcutAction>{
      'playorpause': PlayerShortcutAction.playOrPause,
      'forward': PlayerShortcutAction.forward,
      'rewind': PlayerShortcutAction.rewind,
      'next': PlayerShortcutAction.next,
      'prev': PlayerShortcutAction.prev,
      'volumeup': PlayerShortcutAction.volumeUp,
      'volumedown': PlayerShortcutAction.volumeDown,
      'togglemute': PlayerShortcutAction.toggleMute,
      'fullscreen': PlayerShortcutAction.fullscreen,
      'screenshot': PlayerShortcutAction.screenshot,
      'skip': PlayerShortcutAction.skip,
      'exitfullscreen': PlayerShortcutAction.exitFullscreen,
      'speed1': PlayerShortcutAction.speed1,
      'speed2': PlayerShortcutAction.speed2,
      'speed3': PlayerShortcutAction.speed3,
      'speedup': PlayerShortcutAction.speedUp,
      'speeddown': PlayerShortcutAction.speedDown,
    };
    final shortcuts = <String, List<String>>{};
    var index = 0;
    for (final command in expected.keys) {
      shortcuts[command] = ['key${index++}'];
    }
    final actual = <PlayerShortcutAction>[];
    final handler = PlayerShortcutHandler(
      shortcuts: shortcuts,
      dispatch: actual.add,
    );
    index = 0;
    for (final action in expected.values) {
      final result = handler.dispatchKey(
        'key${index++}',
        PlayerShortcutPhase.down,
      );
      expect(result.action, action);
      expect(result.consumed, isTrue);
    }
    expect(actual, expected.values);
  });

  test('PlayerItem 实际委托快捷键分发', () {
    final source = File('lib/pages/player/player_item.dart').readAsStringSync();
    expect(source, contains('PlayerShortcutHandler'));
    expect(source, contains('Map<PlayerShortcutAction, void Function()>'));
    expect(source, isNot(contains('handleShortcutLongPress')));
    expect(source, contains('_shortcutHandler.handleKey('));
    expect(source, contains('PlayerShortcutPhase.down'));
    expect(source, contains('PlayerShortcutPhase.repeat'));
    expect(source, contains('PlayerShortcutPhase.up'));
  });
}
