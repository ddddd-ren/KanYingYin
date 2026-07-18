import 'package:media_kit/media_kit.dart';

class TrueHdFallbackPolicy {
  const TrueHdFallbackPolicy();

  bool isTrueHd(AudioTrack track) {
    final values = [track.codec, track.decoder, track.title, track.language]
        .whereType<String>()
        .join(' ')
        .toLowerCase();
    return values.contains('truehd') || values.contains('mlp');
  }

  bool isRelatedError(String error, Iterable<AudioTrack> tracks) {
    final lower = error.toLowerCase();
    if (lower.contains('truehd') || lower.contains('mlp')) return true;
    final hasTrueHd = tracks.any(isTrueHd);
    if (!hasTrueHd) return false;
    final audio = lower.contains('audio') || lower.contains('ao');
    final decoder = lower.contains('decoder') ||
        lower.contains('decode') ||
        lower.contains('codec') ||
        lower.contains('failed');
    return audio && decoder;
  }

  AudioTrack? chooseFallback(Iterable<AudioTrack> tracks,
      {required String currentTrackId}) {
    for (final track in tracks) {
      if (track.id == 'auto' ||
          track.id == 'no' ||
          track.id == currentTrackId) {
        continue;
      }
      if (!isTrueHd(track)) return track;
    }
    return null;
  }
}
