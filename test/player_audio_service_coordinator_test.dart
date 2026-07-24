import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_audio_service_coordinator.dart';
import 'package:kanyingyin/services/audio_controller.dart';

void main() {
  test('绑定系统媒体回调后立即同步有效快照', () async {
    final service = _FakePlayerAudioService();
    final coordinator = PlayerAudioServiceCoordinator(service: service);
    var played = false;

    await coordinator.bindCallbacks(
      onPlay: () async => played = true,
      onPause: () async {},
      onSkipToNext: () async {},
      onSkipToPrevious: () async {},
      onSeek: (_) async {},
      isActive: () => true,
      snapshotProvider: _snapshot,
    );

    expect(service.bindCount, 1);
    expect(service.sessions, hasLength(1));
    await service.onPlay!();
    expect(played, isTrue);
  });

  test('无时长快照不会发布系统媒体状态', () async {
    final service = _FakePlayerAudioService();
    final coordinator = PlayerAudioServiceCoordinator(service: service);

    await coordinator.sync(
      _snapshot().copyWith(duration: Duration.zero),
    );

    expect(service.sessions, isEmpty);
  });

  test('释放协调器时停用会话并清除回调', () async {
    final service = _FakePlayerAudioService();
    final coordinator = PlayerAudioServiceCoordinator(service: service);

    await coordinator.dispose();

    expect(service.deactivateCount, 1);
    expect(service.clearCount, 1);
  });
}

PlayerAudioServiceSnapshot _snapshot() {
  return const PlayerAudioServiceSnapshot(
    mediaId: 'local_0_1',
    title: '测试影片',
    album: '本地文件',
    artist: '第一集',
    duration: Duration(minutes: 24),
    playing: true,
    loading: false,
    buffering: false,
    completed: false,
    updatePosition: Duration(minutes: 1),
    bufferedPosition: Duration(minutes: 2),
    speed: 1,
    queueIndex: 0,
    canSkipToNext: true,
    canSkipToPrevious: false,
  );
}

class _FakePlayerAudioService implements PlayerAudioServicePort {
  int bindCount = 0;
  int clearCount = 0;
  int deactivateCount = 0;
  AudioCallback? onPlay;
  final List<PlayerAudioServiceSnapshot> sessions = [];

  @override
  Future<void> bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioCallback onSkipToNext,
    required AudioCallback onSkipToPrevious,
    required AudioSeekCallback onSeek,
  }) async {
    bindCount++;
    this.onPlay = onPlay;
  }

  @override
  void clearCallbacks() => clearCount++;

  @override
  Future<void> deactivate() async => deactivateCount++;

  @override
  Future<void> updateSession(PlayerAudioServiceSnapshot snapshot) async {
    sessions.add(snapshot);
  }
}
