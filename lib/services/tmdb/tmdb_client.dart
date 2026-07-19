import 'package:dio/dio.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/utils/network_settings_config_factory.dart';

abstract class ITmdbClient {
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  });

  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  });
}

class TmdbClient implements ITmdbClient {
  final String apiKey;
  final Dio _dio;

  TmdbClient({required this.apiKey, Dio? dio})
      : _dio = dio ?? _createDefaultDio();

  static Dio _createDefaultDio() {
    final config = NetworkSettingsConfigFactory.create(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    );
    final dio = DioFactory.createForConfig(
      config,
      interceptors: const [],
    );
    dio.options.baseUrl = 'https://api.themoviedb.org/3';
    return dio;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    _validateKey();
    final response = await _dio.get<Map<String, dynamic>>(
      '/search/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}',
      queryParameters: {
        ..._authenticationQuery,
        'query': query,
        'language': language,
        'include_adult': false,
      },
      options: _authenticationOptions,
    );
    final results = response.data?['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<Object?, Object?>>()
        .map((item) => _fromJson(
              Map<String, dynamic>.from(item),
              mediaType,
              language,
            ))
        .toList(growable: false);
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    final primary = await _detailsForLanguage(id, mediaType, language);
    if (language == 'en-US' ||
        (_hasText(primary.overview) &&
            _hasText(primary.posterUrl) &&
            _hasText(primary.backdropUrl) &&
            _hasCompleteSeasonArtwork(primary.seasons))) {
      return primary;
    }
    final fallback = await _detailsForLanguage(id, mediaType, 'en-US');
    return primary.copyWith(
      overview:
          _hasText(primary.overview) ? primary.overview : fallback.overview,
      posterUrl:
          _hasText(primary.posterUrl) ? primary.posterUrl : fallback.posterUrl,
      backdropUrl: _hasText(primary.backdropUrl)
          ? primary.backdropUrl
          : fallback.backdropUrl,
      seasons: _mergeSeasons(primary.seasons, fallback.seasons),
    );
  }

  Future<TmdbMetadata> _detailsForLanguage(
    int id,
    TmdbMediaType mediaType,
    String language,
  ) async {
    _validateKey();
    final response = await _dio.get<Map<String, dynamic>>(
      '/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}/$id',
      queryParameters: {..._authenticationQuery, 'language': language},
      options: _authenticationOptions,
    );
    return _fromJson(response.data ?? const {}, mediaType, language);
  }

  TmdbMetadata _fromJson(
    Map<String, dynamic> json,
    TmdbMediaType mediaType,
    String language,
  ) {
    return TmdbMetadata(
      id: _asInt(json['id']),
      mediaType: mediaType,
      title: _asString(
              json[mediaType == TmdbMediaType.movie ? 'title' : 'name']) ??
          '',
      originalTitle: _asString(json[mediaType == TmdbMediaType.movie
          ? 'original_title'
          : 'original_name']),
      overview: _asString(json['overview']),
      releaseDate: _asString(json[mediaType == TmdbMediaType.movie
          ? 'release_date'
          : 'first_air_date']),
      rating: _asDouble(json['vote_average']),
      posterUrl: _asString(json['poster_path']),
      backdropUrl: _asString(json['backdrop_path']),
      language: language,
      matchedAt: DateTime.now(),
      matchConfidence: 0,
      seasons: _seasonsFromJson(json, mediaType),
    );
  }

  List<TmdbSeasonMetadata> _seasonsFromJson(
    Map<String, dynamic> json,
    TmdbMediaType mediaType,
  ) {
    final rawSeasons = json['seasons'];
    if (mediaType != TmdbMediaType.tv || rawSeasons is! List) {
      return const <TmdbSeasonMetadata>[];
    }
    final seasons = rawSeasons
        .whereType<Map<Object?, Object?>>()
        .map(
          (value) => _seasonFromJson(Map<String, dynamic>.from(value)),
        )
        .where((value) => value.seasonNumber > 0)
        .toList(growable: false)
      ..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
    return seasons;
  }

  TmdbSeasonMetadata _seasonFromJson(Map<String, dynamic> json) {
    return TmdbSeasonMetadata(
      id: _asInt(json['id']),
      seasonNumber: _asInt(json['season_number']),
      name: _asString(json['name']) ?? '',
      episodeCount: _asInt(json['episode_count']),
      overview: _asString(json['overview']),
      airDate: _asString(json['air_date']),
      posterUrl: _asString(json['poster_path']),
    );
  }

  List<TmdbSeasonMetadata> _mergeSeasons(
    List<TmdbSeasonMetadata> primary,
    List<TmdbSeasonMetadata> fallback,
  ) {
    final fallbackByNumber = <int, TmdbSeasonMetadata>{
      for (final season in fallback) season.seasonNumber: season,
    };
    return primary.map((season) {
      final fallbackSeason = fallbackByNumber[season.seasonNumber];
      if (fallbackSeason == null) return season;
      return season.copyWith(
        name: _hasText(season.name) ? season.name : fallbackSeason.name,
        episodeCount: season.episodeCount > 0
            ? season.episodeCount
            : fallbackSeason.episodeCount,
        overview: _hasText(season.overview)
            ? season.overview
            : fallbackSeason.overview,
        airDate:
            _hasText(season.airDate) ? season.airDate : fallbackSeason.airDate,
        posterUrl: _hasText(season.posterUrl)
            ? season.posterUrl
            : fallbackSeason.posterUrl,
      );
    }).toList(growable: false);
  }

  void _validateKey() {
    if (apiKey.trim().isEmpty) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
  }

  bool get _usesBearerToken =>
      apiKey.trim().startsWith('eyJ') || apiKey.trim().length > 64;

  Map<String, dynamic> get _authenticationQuery =>
      _usesBearerToken ? const {} : {'api_key': apiKey.trim()};

  Options? get _authenticationOptions => _usesBearerToken
      ? Options(headers: {'Authorization': 'Bearer ${apiKey.trim()}'})
      : null;

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  bool _hasCompleteSeasonArtwork(List<TmdbSeasonMetadata> seasons) =>
      seasons.isNotEmpty &&
      seasons.every((season) => _hasText(season.posterUrl));

  int _asInt(Object? value) => value is num ? value.toInt() : 0;
  double? _asDouble(Object? value) => value is num ? value.toDouble() : null;
  String? _asString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
