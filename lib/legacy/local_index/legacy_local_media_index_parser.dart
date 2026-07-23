import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

/// 只负责读取旧版本地媒体索引中的 Bangumi 字段。
abstract final class LegacyLocalMediaIndexParser {
  static TmdbMetadata? parseTmdb(Map<String, dynamic> json) {
    try {
      final id = _int(json['bangumiId']);
      if (id == null || id <= 0) return null;
      return TmdbMetadata(
        id: id,
        mediaType: TmdbMediaType.tv,
        title: _text(json['bangumiNameCn']) ?? _text(json['bangumiName']) ?? '',
        originalTitle: _text(json['bangumiName']),
        overview: _text(json['bangumiSummary']),
        releaseDate: _text(json['bangumiAirDate']),
        rating: _double(json['bangumiRatingScore']),
        posterUrl: _text(json['bangumiCoverUrl']),
        language: 'zh-CN',
        matchedAt: _date(json['indexedAtMillis']),
        matchConfidence: 0,
      );
    } on Object {
      return null;
    }
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static DateTime _date(Object? value) {
    final millis = _int(value) ?? 0;
    return millis <= 0
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
