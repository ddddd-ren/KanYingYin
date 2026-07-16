enum TmdbMediaType { movie, tv }

enum TmdbScrapeStatus { none, pending, matched, failed }

class TmdbMetadata {
  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? releaseDate;
  final double? rating;
  final String? posterUrl;
  final String? backdropUrl;
  final String language;
  final DateTime matchedAt;
  final double matchConfidence;

  const TmdbMetadata({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.language,
    required this.matchedAt,
    required this.matchConfidence,
    this.originalTitle,
    this.overview,
    this.releaseDate,
    this.rating,
    this.posterUrl,
    this.backdropUrl,
  });

  factory TmdbMetadata.fromJson(Map<String, dynamic> json) {
    return TmdbMetadata(
      id: _asInt(json['id']),
      mediaType: TmdbMediaType.values.firstWhere(
        (value) => value.name == json['mediaType'],
        orElse: () => TmdbMediaType.tv,
      ),
      title: json['title'] as String? ?? '',
      originalTitle: _asString(json['originalTitle']),
      overview: _asString(json['overview']),
      releaseDate: _asString(json['releaseDate']),
      rating: _asDouble(json['rating']),
      posterUrl: _asString(json['posterUrl']),
      backdropUrl: _asString(json['backdropUrl']),
      language: json['language'] as String? ?? 'zh-CN',
      matchedAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(json['matchedAtMillis']),
      ),
      matchConfidence: _asDouble(json['matchConfidence']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaType': mediaType.name,
      'title': title,
      if (originalTitle != null) 'originalTitle': originalTitle,
      if (overview != null) 'overview': overview,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (rating != null) 'rating': rating,
      if (posterUrl != null) 'posterUrl': posterUrl,
      if (backdropUrl != null) 'backdropUrl': backdropUrl,
      'language': language,
      'matchedAtMillis': matchedAt.millisecondsSinceEpoch,
      'matchConfidence': matchConfidence,
    };
  }

  TmdbMetadata copyWith({
    String? title,
    String? originalTitle,
    String? overview,
    String? releaseDate,
    double? rating,
    String? posterUrl,
    String? backdropUrl,
    String? language,
    DateTime? matchedAt,
    double? matchConfidence,
  }) {
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      overview: overview ?? this.overview,
      releaseDate: releaseDate ?? this.releaseDate,
      rating: rating ?? this.rating,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      language: language ?? this.language,
      matchedAt: matchedAt ?? this.matchedAt,
      matchConfidence: matchConfidence ?? this.matchConfidence,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _asString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
