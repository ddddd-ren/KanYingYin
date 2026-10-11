import 'package:kanyingyin/modules/local/tmdb_image_override.dart';

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
    this.imageOverride = const TmdbImageOverride(),
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
      imageOverride: TmdbImageOverride.fromJson(json['imageOverride']),
    );
  }

  final int id;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final String? stillUrl;
  final double? rating;
  final TmdbImageOverride imageOverride;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'episodeNumber': episodeNumber,
        'name': name,
        if (overview != null) 'overview': overview,
        if (airDate != null) 'airDate': airDate,
        if (stillUrl != null) 'stillUrl': stillUrl,
        if (rating != null) 'rating': rating,
        if (!imageOverride.isEmpty) 'imageOverride': imageOverride.toJson(),
      };

  TmdbEpisodeMetadata copyWith({
    String? name,
    String? overview,
    String? airDate,
    String? stillUrl,
    double? rating,
    TmdbImageOverride? imageOverride,
  }) {
    return TmdbEpisodeMetadata(
      id: id,
      episodeNumber: episodeNumber,
      name: name ?? this.name,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
      stillUrl: stillUrl ?? this.stillUrl,
      rating: rating ?? this.rating,
      imageOverride: imageOverride ?? this.imageOverride,
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
            rating == other.rating &&
            imageOverride == other.imageOverride;
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
        imageOverride,
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
    this.imageOverride = const TmdbImageOverride(),
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
      imageOverride: TmdbImageOverride.fromJson(json['imageOverride']),
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
  final TmdbImageOverride imageOverride;

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
        if (!imageOverride.isEmpty) 'imageOverride': imageOverride.toJson(),
      };

  TmdbSeasonMetadata copyWith({
    String? name,
    int? episodeCount,
    String? overview,
    String? airDate,
    String? posterUrl,
    String? posterCachePath,
    bool clearPosterCachePath = false,
    List<TmdbEpisodeMetadata>? episodes,
    TmdbImageOverride? imageOverride,
  }) {
    return TmdbSeasonMetadata(
      id: id,
      seasonNumber: seasonNumber,
      name: name ?? this.name,
      episodeCount: episodeCount ?? this.episodeCount,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
      posterUrl: posterUrl ?? this.posterUrl,
      posterCachePath:
          clearPosterCachePath ? null : posterCachePath ?? this.posterCachePath,
      episodes: episodes ?? this.episodes,
      imageOverride: imageOverride ?? this.imageOverride,
    );
  }

  TmdbSeasonMetadata clearPosterCache() => copyWith(clearPosterCachePath: true);

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
            _listsEqual(episodes, other.episodes) &&
            imageOverride == other.imageOverride;
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
        imageOverride,
      );
}

class TmdbPersonMetadata {
  const TmdbPersonMetadata({
    required this.id,
    required this.name,
    this.character,
    this.job,
    this.profileUrl,
  });

  factory TmdbPersonMetadata.fromJson(Map<Object?, Object?> json) {
    return TmdbPersonMetadata(
      id: _asInt(json['id']),
      name: _asString(json['name']) ?? '',
      character: _asString(json['character']),
      job: _asString(json['job']),
      profileUrl: _asString(json['profileUrl'] ?? json['profile_path']),
    );
  }

  final int id;
  final String name;
  final String? character;
  final String? job;
  final String? profileUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        if (character != null) 'character': character,
        if (job != null) 'job': job,
        if (profileUrl != null) 'profileUrl': profileUrl,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TmdbPersonMetadata &&
            id == other.id &&
            name == other.name &&
            character == other.character &&
            job == other.job &&
            profileUrl == other.profileUrl;
  }

  @override
  int get hashCode => Object.hash(id, name, character, job, profileUrl);
}

class TmdbSimilarMetadata {
  const TmdbSimilarMetadata({
    required this.id,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterUrl,
    this.rating,
  });

  factory TmdbSimilarMetadata.fromJson(
    Map<Object?, Object?> json, {
    required TmdbMediaType fallbackMediaType,
  }) {
    final rawMediaType = _asString(json['mediaType'] ?? json['media_type']);
    return TmdbSimilarMetadata(
      id: _asInt(json['id']),
      mediaType: rawMediaType == TmdbMediaType.movie.name
          ? TmdbMediaType.movie
          : rawMediaType == TmdbMediaType.tv.name
              ? TmdbMediaType.tv
              : fallbackMediaType,
      title: _asString(json['title'] ?? json['name']) ?? '',
      originalTitle: _asString(json['originalTitle'] ??
          json['original_title'] ??
          json['original_name']),
      overview: _asString(json['overview']),
      posterUrl: _asString(json['posterUrl'] ?? json['poster_path']),
      rating: _asDouble(json['rating'] ?? json['vote_average']),
    );
  }

  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterUrl;
  final double? rating;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'mediaType': mediaType.name,
        'title': title,
        if (originalTitle != null) 'originalTitle': originalTitle,
        if (overview != null) 'overview': overview,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (rating != null) 'rating': rating,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TmdbSimilarMetadata &&
            id == other.id &&
            mediaType == other.mediaType &&
            title == other.title &&
            originalTitle == other.originalTitle &&
            overview == other.overview &&
            posterUrl == other.posterUrl &&
            rating == other.rating;
  }

  @override
  int get hashCode => Object.hash(
      id, mediaType, title, originalTitle, overview, posterUrl, rating);
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
  final List<TmdbPersonMetadata> cast;
  final List<TmdbPersonMetadata> directors;
  final List<TmdbSimilarMetadata> similar;
  final TmdbImageOverride imageOverride;

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
    this.cast = const <TmdbPersonMetadata>[],
    this.directors = const <TmdbPersonMetadata>[],
    this.similar = const <TmdbSimilarMetadata>[],
    this.imageOverride = const TmdbImageOverride(),
  });

  factory TmdbMetadata.fromJson(Map<String, dynamic> json) {
    final parsedMediaType = TmdbMediaType.values
        .where((value) => value.name == json['mediaType'])
        .firstOrNull;
    return TmdbMetadata(
      id: _asInt(json['id']),
      mediaType: parsedMediaType ?? TmdbMediaType.tv,
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
      // 未知类型仅沿用旧结构兼容，不能保留可靠匹配的证据。
      matchConfidence:
          parsedMediaType == null ? 0 : _asDouble(json['matchConfidence']) ?? 0,
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
      cast: _peopleFromJson(json['cast']),
      directors: _peopleFromJson(json['directors']),
      similar: _similarFromJson(
        json['similar'],
        fallbackMediaType: parsedMediaType ?? TmdbMediaType.tv,
      ),
      imageOverride: TmdbImageOverride.fromJson(json['imageOverride']),
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
      if (cast.isNotEmpty)
        'cast': cast.map((item) => item.toJson()).toList(growable: false),
      if (directors.isNotEmpty)
        'directors':
            directors.map((item) => item.toJson()).toList(growable: false),
      if (similar.isNotEmpty)
        'similar': similar.map((item) => item.toJson()).toList(growable: false),
      if (!imageOverride.isEmpty) 'imageOverride': imageOverride.toJson(),
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
    List<TmdbPersonMetadata>? cast,
    List<TmdbPersonMetadata>? directors,
    List<TmdbSimilarMetadata>? similar,
    TmdbImageOverride? imageOverride,
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
      cast: cast ?? this.cast,
      directors: directors ?? this.directors,
      similar: similar ?? this.similar,
      imageOverride: imageOverride ?? this.imageOverride,
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
            _listsEqual(seasons, other.seasons) &&
            _listsEqual(cast, other.cast) &&
            _listsEqual(directors, other.directors) &&
            _listsEqual(similar, other.similar) &&
            imageOverride == other.imageOverride;
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
        Object.hashAll(cast),
        Object.hashAll(directors),
        Object.hashAll(similar),
        imageOverride,
      ]);
}

List<TmdbPersonMetadata> _peopleFromJson(Object? value) {
  if (value is! List) return const <TmdbPersonMetadata>[];
  return value
      .whereType<Map<Object?, Object?>>()
      .map(TmdbPersonMetadata.fromJson)
      .where((person) => person.id > 0 && person.name.isNotEmpty)
      .toList(growable: false);
}

List<TmdbSimilarMetadata> _similarFromJson(
  Object? value, {
  required TmdbMediaType fallbackMediaType,
}) {
  if (value is! List) return const <TmdbSimilarMetadata>[];
  return value
      .whereType<Map<Object?, Object?>>()
      .map(
        (json) => TmdbSimilarMetadata.fromJson(
          json,
          fallbackMediaType: fallbackMediaType,
        ),
      )
      .where((item) => item.id > 0 && item.title.isNotEmpty)
      .toList(growable: false);
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
