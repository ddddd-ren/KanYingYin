import 'package:media_kit/media_kit.dart';

enum EmbeddedTrackType { audio, subtitle }

enum TrackLanguageKind {
  mandarin,
  cantonese,
  taiwaneseMandarin,
  simplifiedChinese,
  bilingualChinese,
  traditionalChinese,
  english,
  unknown,
}

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
    required this.primaryLabel,
    required this.detailLabel,
    required this.originalTitle,
  });

  final String id;
  final EmbeddedTrackType type;
  final TrackLanguageKind kind;
  final String primaryLabel;
  final String detailLabel;
  final String originalTitle;

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
    final source = '${language ?? ''} ${title ?? ''}'.toLowerCase();
    final kind = _detectKind(source, type);
    final languageLabel = _languageLabel(kind, type);
    final safeTitle = title?.trim() ?? '';
    final primary = languageLabel == '未知语种'
        ? '未知语种 · 轨道 $id${safeTitle.isEmpty ? '' : ' · $safeTitle'}'
        : languageLabel;
    final details = <String>[
      if (safeTitle.isNotEmpty && !primary.contains(safeTitle)) safeTitle,
      if (codec != null && codec.trim().isNotEmpty) _codecLabel(codec),
      if (type == EmbeddedTrackType.audio)
        _channelLabel(channels, channelsCount),
    ].where((value) => value.isNotEmpty).toList();
    return EmbeddedTrackInfo(
      id: id,
      type: type,
      kind: kind,
      primaryLabel: primary,
      detailLabel: details.join(' · '),
      originalTitle: safeTitle,
    );
  }

  static TrackLanguageKind _detectKind(
    String source,
    EmbeddedTrackType type,
  ) {
    bool hasAny(Iterable<String> values) => values.any(source.contains);
    if (hasAny(['粤语', '广东话', 'cantonese', 'yue'])) {
      return TrackLanguageKind.cantonese;
    }
    if (hasAny(['台配', '台湾国语'])) {
      return TrackLanguageKind.taiwaneseMandarin;
    }
    if (type == EmbeddedTrackType.subtitle) {
      if (hasAny(['简繁', '双语'])) return TrackLanguageKind.bilingualChinese;
      if (hasAny(['繁体', '繁中', 'traditional', 'zh-hant'])) {
        return TrackLanguageKind.traditionalChinese;
      }
      if (hasAny(['简体', '简中', 'simplified', 'zh-hans', 'chs'])) {
        return TrackLanguageKind.simplifiedChinese;
      }
    }
    final languageCode = RegExp(r'(^|\s)(zh|zho|chi|zh-cn)(\s|$)');
    if (languageCode.hasMatch(source) ||
        hasAny(['中文', '国语', '普通话', 'mandarin'])) {
      return type == EmbeddedTrackType.audio
          ? TrackLanguageKind.mandarin
          : TrackLanguageKind.simplifiedChinese;
    }
    if (RegExp(r'(^|\s)(en|eng)(\s|$)').hasMatch(source) ||
        source.contains('english')) {
      return TrackLanguageKind.english;
    }
    return TrackLanguageKind.unknown;
  }

  static String _languageLabel(
    TrackLanguageKind kind,
    EmbeddedTrackType type,
  ) =>
      switch (kind) {
        TrackLanguageKind.mandarin => '国语 / Mandarin',
        TrackLanguageKind.cantonese => '粤语 / Cantonese',
        TrackLanguageKind.taiwaneseMandarin => '台配',
        TrackLanguageKind.simplifiedChinese => '简体中文',
        TrackLanguageKind.bilingualChinese => '简繁双语',
        TrackLanguageKind.traditionalChinese => '繁体中文',
        TrackLanguageKind.english => '英语 / English',
        TrackLanguageKind.unknown => '未知语种',
      };

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
