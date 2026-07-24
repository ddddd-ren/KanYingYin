import 'package:kanyingyin/services/audio_controller.dart';
import 'package:kanyingyin/utils/logger.dart';

class PlayerAudioServiceSnapshot {
  const PlayerAudioServiceSnapshot({
    required this.mediaId,
    required this.title,
    required this.album,
    required this.artist,
    required this.duration,
    required this.playing,
    required this.loading,
    required this.buffering,
    required this.completed,
    required this.updatePosition,
    required this.bufferedPosition,
    required this.speed,
    required this.queueIndex,
    required this.canSkipToNext,
    required this.canSkipToPrevious,
    this.artUri,
  });

  final String mediaId;
  final String title;
  final String album;
  final String artist;
  final Uri? artUri;
  final Duration duration;
  final bool playing;
  final bool loading;
  final bool buffering;
  final bool completed;
  final Duration updatePosition;
  final Duration bufferedPosition;
  final double speed;
  final int queueIndex;
  final bool canSkipToNext;
  final bool canSkipToPrevious;

  PlayerAudioServiceSnapshot copyWith({Duration? duration}) {
    return PlayerAudioServiceSnapshot(
      mediaId: mediaId,
      title: title,
      album: album,
      artist: artist,
      artUri: artUri,
      duration: duration ?? this.duration,
      playing: playing,
      loading: loading,
      buffering: buffering,
      completed: completed,
      updatePosition: updatePosition,
      bufferedPosition: bufferedPosition,
      speed: speed,
      queueIndex: queueIndex,
      canSkipToNext: canSkipToNext,
      canSkipToPrevious: canSkipToPrevious,
    );
  }
}

abstract interface class PlayerAudioServicePort {
  Future<void> bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioCallback onSkipToNext,
    required AudioCallback onSkipToPrevious,
    required AudioSeekCallback onSeek,
  });

  Future<void> updateSession(PlayerAudioServiceSnapshot snapshot);

  Future<void> deactivate();

  void clearCallbacks();
}

class AudioControllerPlayerAudioService implements PlayerAudioServicePort {
  AudioControllerPlayerAudioService(this._controller);

  final AudioController _controller;

  @override
  Future<void> bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioCallback onSkipToNext,
    required AudioCallback onSkipToPrevious,
    required AudioSeekCallback onSeek,
  }) {
    return _controller.bindCallbacks(
      onPlay: onPlay,
      onPause: onPause,
      onSkipToNext: onSkipToNext,
      onSkipToPrevious: onSkipToPrevious,
      onSeek: onSeek,
    );
  }

  @override
  Future<void> updateSession(PlayerAudioServiceSnapshot snapshot) {
    return _controller.updateSession(
      mediaId: snapshot.mediaId,
      title: snapshot.title,
      album: snapshot.album,
      artist: snapshot.artist,
      artUri: snapshot.artUri,
      duration: snapshot.duration,
      playing: snapshot.playing,
      loading: snapshot.loading,
      buffering: snapshot.buffering,
      completed: snapshot.completed,
      updatePosition: snapshot.updatePosition,
      bufferedPosition: snapshot.bufferedPosition,
      speed: snapshot.speed,
      queueIndex: snapshot.queueIndex,
      canSkipToNext: snapshot.canSkipToNext,
      canSkipToPrevious: snapshot.canSkipToPrevious,
    );
  }

  @override
  Future<void> deactivate() => _controller.deactivate();

  @override
  void clearCallbacks() => _controller.clearCallbacks();
}

/// 管理播放器与系统媒体会话之间的回调绑定和状态发布。
class PlayerAudioServiceCoordinator {
  PlayerAudioServiceCoordinator({required PlayerAudioServicePort service})
      : _service = service;

  final PlayerAudioServicePort _service;

  Future<void> bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioCallback onSkipToNext,
    required AudioCallback onSkipToPrevious,
    required AudioSeekCallback onSeek,
    required bool Function() isActive,
    required PlayerAudioServiceSnapshot? Function() snapshotProvider,
  }) async {
    try {
      await _service.bindCallbacks(
        onPlay: onPlay,
        onPause: onPause,
        onSkipToNext: onSkipToNext,
        onSkipToPrevious: onSkipToPrevious,
        onSeek: onSeek,
      );
      if (!isActive()) return;
      await sync(snapshotProvider());
    } catch (error, stackTrace) {
      AppLogger().w(
        'AudioController: failed to bind callbacks',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> sync(PlayerAudioServiceSnapshot? snapshot) async {
    if (snapshot == null || snapshot.duration <= Duration.zero) return;
    try {
      await _service.updateSession(snapshot);
    } catch (error, stackTrace) {
      AppLogger().w(
        'AudioController: failed to sync playback state',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    _service.clearCallbacks();
    await _service.deactivate();
  }
}
