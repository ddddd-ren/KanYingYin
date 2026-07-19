enum TmdbMediaType { movie, tv }

enum TmdbScrapeStatus { none, pending, matched, failed }

class TmdbSeasonMetadata {
  const TmdbSeasonMetadata({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.overview,
    this.airDate,
    this.posterUrl,
    this.posterCachePath,
  });

  factory TmdbSeasonMetadata.fromJson(Map<String, dynamic> json) {
    return TmdbSeasonMetadata(
      id: _asInt(json['id']),
      seasonNumber: _asInt(json['seasonNumber']),
      name: json['name'] as String? ?? '',
      episodeCount: _asInt(json['episodeCount']),
      overview: _asString(json['overview']),
      airDate: _asString(json['airDate']),
      posterUrl: _asString(json['posterUrl']),
      posterCachePath: _asString(json['posterCachePath']),
    );
  }

  final int id;
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? overview;
  final String? airDate;
  final String? posterUrl;
  final String? posterCachePath;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'seasonNumber': seasonNumber,
        'name': name,
        'episodeCount': episodeCount,
        if (overview != null) 'overview': overview,
        if (airDate != null) 'airDate': airDate,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (posterCachePath != null) 'posterCachePath': posterCachePath,
      };

  TmdbSeasonMetadata copyWith({
    String? name,
    int? episodeCount,
    String? overview,
    String? airDate,
    String? posterUrl,
    String? posterCachePath,
  }) {
    return TmdbSeasonMetadata(
      id: id,
      seasonNumber: seasonNumber,
      name: name ?? this.name,
      episodeCount: episodeCount ?? this.episodeCount,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
      posterUrl: posterUrl ?? this.posterUrl,
      posterCachePath: posterCachePath ?? this.posterCachePath,
    );
  }
}

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
  final List<TmdbSeasonMetadata> seasons;

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
    this.seasons = const <TmdbSeasonMetadata>[],
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
      seasons: json['seasons'] is List
          ? (json['seasons'] as List)
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => TmdbSeasonMetadata.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const <TmdbSeasonMetadata>[],
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
      if (seasons.isNotEmpty)
        'seasons': seasons.map((item) => item.toJson()).toList(growable: false),
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
    List<TmdbSeasonMetadata>? seasons,
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
      seasons: seasons ?? this.seasons,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _asString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
