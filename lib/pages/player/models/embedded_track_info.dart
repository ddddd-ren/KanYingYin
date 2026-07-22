import 'package:media_kit/media_kit.dart';

export 'embedded_track_language.dart';
import 'embedded_track_language.dart';

class EmbeddedTrackSelectionState {
  bool _automaticSelectionCompleted = false;
  bool _audioSelectedManually = false;

  bool get canAutomaticallySelectAudio => !_audioSelectedManually;

  bool beginAutomaticSelection({required bool hasAudioTracks}) {
    if (_automaticSelectionCompleted || !hasAudioTracks) return false;
    _automaticSelectionCompleted = true;
    return true;
  }

  void markAudioSelectedManually() => _audioSelectedManually = true;

  void reset() {
    _automaticSelectionCompleted = false;
    _audioSelectedManually = false;
  }
}

class SubtitleTrackSelectionState {
  int _revision = 0;
  bool _manualSelectionMade = false;

  int beginAutomaticSelection() => _revision;

  bool canApplyAutomaticSelection(int revision) =>
      !_manualSelectionMade && revision == _revision;

  void markManualSelection() {
    _manualSelectionMade = true;
    _revision++;
  }

  void reset() {
    _manualSelectionMade = false;
    _revision++;
  }
}

class EmbeddedTrackInfo {
  const EmbeddedTrackInfo({
    required this.id,
    required this.type,
    required this.kind,
    required this.language,
    required this.primaryLabel,
    required this.detailLabel,
    required this.originalTitle,
    required this.originalCodec,
  });

  final String id;
  final EmbeddedTrackType type;
  final TrackLanguageKind kind;
  final TrackLanguageChoice language;
  final String primaryLabel;
  final String detailLabel;
  final String originalTitle;
  final String originalCodec;

  bool get isLanguageResolved => language.isResolved;

  EmbeddedTrackInfo withLanguage(TrackLanguageChoice value) {
    final label = value.isResolved
        ? value.label
        : '${type == EmbeddedTrackType.subtitle ? '字幕' : '音轨'}轨道 $id';
    return EmbeddedTrackInfo(
      id: id,
      type: type,
      kind: value.kind,
      language: value,
      primaryLabel: label,
      detailLabel: detailLabel,
      originalTitle: originalTitle,
      originalCodec: originalCodec,
    );
  }

  factory EmbeddedTrackInfo.fromAudio(AudioTrack track) => _fromTrack(
        id: track.id,
        type: EmbeddedTrackType.audio,
        title: track.title,
        language: track.language,
        codec: track.codec,
        channels: track.channels,
        channelsCount: track.channelscount ?? track.audiochannels,
      );

  factory EmbeddedTrackInfo.fromSubtitle(SubtitleTrack track) => _fromTrack(
        id: track.id,
        type: EmbeddedTrackType.subtitle,
        title: track.title,
        language: track.language,
        codec: track.codec,
      );

  static EmbeddedTrackInfo _fromTrack({
    required String id,
    required EmbeddedTrackType type,
    String? title,
    String? language,
    String? codec,
    String? channels,
    int? channelsCount,
  }) {
    final languageChoice = trackLanguageFromMetadata(
      language,
      title,
      type: type,
    );
    final safeTitle = title?.trim() ?? '';
    final primary = languageChoice.isResolved
        ? languageChoice.label
        : '${type == EmbeddedTrackType.subtitle ? '字幕' : '音轨'}轨道 $id';
    final details = <String>[
      if (safeTitle.isNotEmpty && !primary.contains(safeTitle)) safeTitle,
      if (codec != null && codec.trim().isNotEmpty) _codecLabel(codec),
      if (type == EmbeddedTrackType.audio)
        _channelLabel(channels, channelsCount),
    ].where((value) => value.isNotEmpty).toList();
    return EmbeddedTrackInfo(
      id: id,
      type: type,
      kind: languageChoice.kind,
      language: languageChoice,
      primaryLabel: primary,
      detailLabel: details.join(' · '),
      originalTitle: safeTitle,
      originalCodec: codec?.trim() ?? '',
    );
  }

  static String _codecLabel(String codec) {
    final lower = codec.toLowerCase();
    if (lower.contains('truehd')) return 'TrueHD';
    if (lower.contains('pgs')) return 'PGS';
    if (lower == 'subrip') return 'SRT';
    return codec.toUpperCase();
  }

  static String _channelLabel(String? channels, int? count) {
    if (count != null) {
      if (count == 1) return '1.0';
      if (count == 2) return '2.0';
      if (count == 6) return '5.1';
      if (count == 8) return '7.1';
      return '$count 声道';
    }
    return channels?.trim() ?? '';
  }
}

EmbeddedTrackInfo? selectPreferredAudioTrack(
  List<EmbeddedTrackInfo> tracks, {
  String? defaultTrackId,
}) {
  for (final kind in const [
    TrackLanguageKind.mandarin,
    TrackLanguageKind.cantonese,
    TrackLanguageKind.taiwaneseMandarin,
  ]) {
    final match = tracks.where((track) => track.kind == kind).firstOrNull;
    if (match != null) return match;
  }
  return tracks.where((track) => track.id == defaultTrackId).firstOrNull ??
      tracks.firstOrNull;
}

EmbeddedTrackInfo? selectPreferredSubtitleTrack(
  List<EmbeddedTrackInfo> tracks, {
  String? defaultTrackId,
}) {
  for (final kind in const [
    TrackLanguageKind.simplifiedChinese,
    TrackLanguageKind.bilingualChinese,
    TrackLanguageKind.traditionalChinese,
  ]) {
    final match = tracks.where((track) => track.kind == kind).firstOrNull;
    if (match != null) return match;
  }
  final defaultTrack =
      tracks.where((track) => track.id == defaultTrackId).firstOrNull;
  return defaultTrack;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
