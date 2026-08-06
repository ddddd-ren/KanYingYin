import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/tv_remote_key_policy.dart';

void main() {
  test('标准 Android TV 遥控器标签映射为稳定语义', () {
    const expected = <String, TvRemoteAction>{
      'Enter': TvRemoteAction.activate,
      'Select': TvRemoteAction.activate,
      'Media Play Pause': TvRemoteAction.playPause,
      'Arrow Left': TvRemoteAction.seekBackward,
      'Arrow Right': TvRemoteAction.seekForward,
      'Arrow Up': TvRemoteAction.volumeUp,
      'Arrow Down': TvRemoteAction.volumeDown,
      'Escape': TvRemoteAction.back,
      'Menu': TvRemoteAction.menu,
    };

    for (final entry in expected.entries) {
      expect(TvRemoteKeyPolicy.actionFor(entry.key), entry.value);
    }
  });

  test('兼容游戏手柄、数字回车和空/未知标签', () {
    expect(
      TvRemoteKeyPolicy.actionFor('GameButtonA'),
      TvRemoteAction.activate,
    );
    expect(
      TvRemoteKeyPolicy.actionFor('NumpadEnter'),
      TvRemoteAction.activate,
    );
    expect(TvRemoteKeyPolicy.actionFor(''), isNull);
    expect(TvRemoteKeyPolicy.actionFor('Unmapped Remote Key'), isNull);
  });

  test('标签前后空白和大小写差异不改变语义', () {
    expect(
      TvRemoteKeyPolicy.actionFor('  arrow left '),
      TvRemoteAction.seekBackward,
    );
    expect(
      TvRemoteKeyPolicy.actionFor('MEDIA PLAY PAUSE'),
      TvRemoteAction.playPause,
    );
  });
}
