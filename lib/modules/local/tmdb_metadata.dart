enum TmdbMediaType { movie, tv }

enum TmdbScrapeStatus { none, pending, matched, failed }

class TmdbEpisodeMetadata {
  const TmdbEpisodeMetadata({
    required this.id,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.airDate,
    this.stillUrl,
    this.rating,
  });

  factory TmdbEpisodeMetadata.fromJson(Map<String, dynamic> json) {
    return TmdbEpisodeMetadata(
      id: _asInt(json['id']),
      episodeNumber: _asInt(json['episodeNumber']),
      name: json['name'] as String? ?? '',
      overview: _asString(json['overview']),
      airDate: _asString(json['airDate']),
      stillUrl: _asString(json['stillUrl']),
      rating: _asDouble(json['rating']),
    );
  }

  final int id;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final String? stillUrl;
  final double? rating;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'episodeNumber': episodeNumber,
        'name': name,
        if (overview != null) 'overview': overview,
        if (airDate != null) 'airDate': airDate,
        if (stillUrl != null) 'stillUrl': stillUrl,
        if (rating != null) 'rating': rating,
      };

  TmdbEpisodeMetadata copyWith({
    String? name,
    String? overview,
    String? airDate,
    String? stillUrl,
    double? rating,
  }) {
    return TmdbEpisodeMetadata(
      id: id,
      episodeNumber: episodeNumber,
      name: name ?? this.name,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
      stillUrl: stillUrl ?? this.stillUrl,
      rating: rating ?? this.rating,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TmdbEpisodeMetadata &&
            id == other.id &&
            episodeNumber == other.episodeNumber &&
            name == other.name &&
            overview == other.overview &&
            airDate == other.airDate &&
            stillUrl == other.stillUrl &&
            rating == other.rating;
  }

  @override
  int get hashCode => Object.hash(
        id,
        episodeNumber,
        name,
        overview,
        airDate,
        stillUrl,
        rating,
      );
}

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
    this.episodes = const <TmdbEpisodeMetadata>[],
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
      episodes: json['episodes'] is List
          ? (json['episodes'] as List)
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => TmdbEpisodeMetadata.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const <TmdbEpisodeMetadata>[],
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
  final List<TmdbEpisodeMetadata> episodes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'seasonNumber': seasonNumber,
        'name': name,
        'episodeCount': episodeCount,
        if (overview != null) 'overview': overview,
        if (airDate != null) 'airDate': airDate,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (posterCachePath != null) 'posterCachePath': posterCachePath,
        if (episodes.isNotEmpty)
          'episodes': episodes.map((item) => item.toJson()).toList(
                growable: false,
              ),
      };

  TmdbSeasonMetadata copyWith({
    String? name,
    int? episodeCount,
    String? overview,
    String? airDate,
    String? posterUrl,
    String? posterCachePath,
    List<TmdbEpisodeMetadata>? episodes,
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
      episodes: episodes ?? this.episodes,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TmdbSeasonMetadata &&
            id == other.id &&
            seasonNumber == other.seasonNumber &&
            name == other.name &&
            episodeCount == other.episodeCount &&
            overview == other.overview &&
            airDate == other.airDate &&
            posterUrl == other.posterUrl &&
            posterCachePath == other.posterCachePath &&
            _listsEqual(episodes, other.episodes);
  }

  @override
  int get hashCode => Object.hash(
        id,
        seasonNumber,
        name,
        episodeCount,
        overview,
        airDate,
        posterUrl,
        posterCachePath,
        Object.hashAll(episodes),
      );
}

class TmdbMetadata {
  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final List<String> aliases;
  final String? originalTitle;
  final String? overview;
  final String? releaseDate;
  final double? rating;
  final double? popularity;
  final int? voteCount;
  final String? posterUrl;
  final String? backdropUrl;
  final String language;
  final DateTime matchedAt;
  final double matchConfidence;
  final List<String> genres;
  final List<TmdbSeasonMetadata> seasons;

  const TmdbMetadata({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.language,
    required this.matchedAt,
    required this.matchConfidence,
    this.aliases = const <String>[],
    this.originalTitle,
    this.overview,
    this.releaseDate,
    this.rating,
    this.popularity,
    this.voteCount,
    this.posterUrl,
    this.backdropUrl,
    this.genres = const <String>[],
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
      aliases: _asStringList(json['aliases']),
      originalTitle: _asString(json['originalTitle']),
      overview: _asString(json['overview']),
      releaseDate: _asString(json['releaseDate']),
      rating: _asDouble(json['rating']),
      popularity: _asDouble(json['popularity']),
      voteCount: _asNullableInt(json['voteCount']),
      posterUrl: _asString(json['posterUrl']),
      backdropUrl: _asString(json['backdropUrl']),
      language: json['language'] as String? ?? 'zh-CN',
      matchedAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(json['matchedAtMillis']),
        isUtc: true,
      ),
      matchConfidence: _asDouble(json['matchConfidence']) ?? 0,
      genres: _asStringList(json['genres']),
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
      if (aliases.isNotEmpty) 'aliases': aliases,
      if (originalTitle != null) 'originalTitle': originalTitle,
      if (overview != null) 'overview': overview,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (rating != null) 'rating': rating,
      if (popularity != null) 'popularity': popularity,
      if (voteCount != null) 'voteCount': voteCount,
      if (posterUrl != null) 'posterUrl': posterUrl,
      if (backdropUrl != null) 'backdropUrl': backdropUrl,
      'language': language,
      'matchedAtMillis': matchedAt.millisecondsSinceEpoch,
      'matchConfidence': matchConfidence,
      if (genres.isNotEmpty) 'genres': genres,
      if (seasons.isNotEmpty)
        'seasons': seasons.map((item) => item.toJson()).toList(growable: false),
    };
  }

  TmdbMetadata copyWith({
    String? title,
    List<String>? aliases,
    String? originalTitle,
    String? overview,
    String? releaseDate,
    double? rating,
    double? popularity,
    int? voteCount,
    String? posterUrl,
    String? backdropUrl,
    String? language,
    DateTime? matchedAt,
    double? matchConfidence,
    List<String>? genres,
    List<TmdbSeasonMetadata>? seasons,
  }) {
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: title ?? this.title,
      aliases: aliases ?? this.aliases,
      originalTitle: originalTitle ?? this.originalTitle,
      overview: overview ?? this.overview,
      releaseDate: releaseDate ?? this.releaseDate,
      rating: rating ?? this.rating,
      popularity: popularity ?? this.popularity,
      voteCount: voteCount ?? this.voteCount,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      language: language ?? this.language,
      matchedAt: matchedAt ?? this.matchedAt,
      matchConfidence: matchConfidence ?? this.matchConfidence,
      genres: genres ?? this.genres,
      seasons: seasons ?? this.seasons,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TmdbMetadata &&
            id == other.id &&
            mediaType == other.mediaType &&
            title == other.title &&
            _listsEqual(aliases, other.aliases) &&
            originalTitle == other.originalTitle &&
            overview == other.overview &&
            releaseDate == other.releaseDate &&
            rating == other.rating &&
            popularity == other.popularity &&
            voteCount == other.voteCount &&
            posterUrl == other.posterUrl &&
            backdropUrl == other.backdropUrl &&
            language == other.language &&
            matchedAt == other.matchedAt &&
            matchConfidence == other.matchConfidence &&
            _listsEqual(genres, other.genres) &&
            _listsEqual(seasons, other.seasons);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        mediaType,
        title,
        Object.hashAll(aliases),
        originalTitle,
        overview,
        releaseDate,
        rating,
        popularity,
        voteCount,
        posterUrl,
        backdropUrl,
        language,
        matchedAt,
        matchConfidence,
        Object.hashAll(genres),
        Object.hashAll(seasons),
      ]);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _asString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final item in value.whereType<String>()) {
    final text = item.trim();
    if (text.isNotEmpty && !result.contains(text)) result.add(text);
  }
  return List<String>.unmodifiable(result);
}

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
