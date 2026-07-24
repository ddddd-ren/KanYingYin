import 'package:kanyingyin/features/player/application/embedded_track_language_preferences.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';

class EmbeddedTrackSession {
  const EmbeddedTrackSession._(this.revision, this.mediaKey);

  final int revision;
  final String mediaKey;
}

/// 将音轨语言指纹与播放器媒体生命周期绑定，拒绝旧异步结果。
class EmbeddedTrackCoordinator {
  EmbeddedTrackCoordinator(this._preferences);

  final EmbeddedTrackLanguagePreferences _preferences;
  int _revision = 0;
  String _mediaKey = '';

  EmbeddedTrackSession beginMedia(String mediaKey) {
    _mediaKey = mediaKey.trim();
    return EmbeddedTrackSession._(++_revision, _mediaKey);
  }

  TrackLanguageChoice? loadChoice(EmbeddedTrackInfo track) {
    final fingerprint = _fingerprint(_mediaKey, track);
    return fingerprint.isEmpty ? null : _preferences.load(fingerprint);
  }

  Future<bool> saveChoice({
    required EmbeddedTrackSession session,
    required EmbeddedTrackInfo track,
    required TrackLanguageChoice choice,
  }) async {
    if (session.revision != _revision || session.mediaKey != _mediaKey) {
      return false;
    }
    final fingerprint = _fingerprint(session.mediaKey, track);
    if (fingerprint.isEmpty) return false;
    await _preferences.save(fingerprint, choice);
    return session.revision == _revision && session.mediaKey == _mediaKey;
  }

  String fingerprintFor(EmbeddedTrackInfo track) =>
      _fingerprint(_mediaKey, track);

  String fingerprintForMedia(String mediaKey, EmbeddedTrackInfo track) =>
      _fingerprint(mediaKey.trim(), track);

  String _fingerprint(String mediaKey, EmbeddedTrackInfo track) {
    if (mediaKey.isEmpty) return '';
    return embeddedTrackLanguageFingerprint(
      mediaKey: mediaKey,
      type: track.type,
      trackId: track.id,
      codec: track.originalCodec,
      title: track.originalTitle,
    );
  }
}
