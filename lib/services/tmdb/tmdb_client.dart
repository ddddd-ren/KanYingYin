import 'package:dio/dio.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_endpoint_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/network_settings_config_factory.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';

typedef TmdbDioFactory = Dio Function();
typedef TmdbProxyRecovery = Future<bool> Function();

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

typedef TmdbClientFactory = ITmdbClient Function(String apiKey);
typedef TmdbScrapeCacheFactory = TmdbScrapeCache Function(String apiKey);

/// 同一 API Key 对应的客户端和请求缓存上下文。
class TmdbClientContext {
  const TmdbClientContext({required this.client, required this.cache});

  final ITmdbClient client;
  final TmdbScrapeCache cache;
}

/// 按 API Key 复用 TMDB 客户端和缓存，避免不同凭据之间共享响应。
class TmdbClientContextRegistry {
  TmdbClientContextRegistry({
    TmdbClientFactory? clientFactory,
    TmdbScrapeCacheFactory? cacheFactory,
  })  : _clientFactory = clientFactory,
        _cacheFactory = cacheFactory;

  final TmdbClientFactory? _clientFactory;
  final TmdbScrapeCacheFactory? _cacheFactory;
  final Map<String, TmdbClientContext> _contexts =
      <String, TmdbClientContext>{};

  TmdbClientContext contextFor(String apiKey) {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'API Key 不能为空');
    }
    final existing = _contexts[normalized];
    if (existing != null) return existing;
    final cache = _cacheFactory?.call(normalized) ?? TmdbScrapeCache();
    final client = _clientFactory?.call(normalized) ??
        TmdbClient(apiKey: normalized, cache: cache);
    final context = TmdbClientContext(client: client, cache: cache);
    _contexts[normalized] = context;
    return context;
  }

  ITmdbClient clientFor(String apiKey) => contextFor(apiKey).client;

  TmdbScrapeCache cacheFor(String apiKey) => contextFor(apiKey).cache;

  /// 清理所有响应并丢弃客户端上下文；不会触碰用户凭据存储。
  void clear() {
    for (final context in _contexts.values) {
      context.cache.clear();
    }
    _contexts.clear();
  }
}

class TmdbClient implements ITmdbClient, ITmdbClientCapabilities {
  final String apiKey;
  Dio _dio;
  final TmdbDioFactory? _dioFactory;
  final TmdbProxyRecovery? _recoverProxy;
  final TmdbScrapeCache? _cache;
  Future<bool>? _rebuildingDio;
  String _preferredBaseUrl = TmdbEndpointPolicy.primaryApiBaseUrl;

  TmdbClient({
    required this.apiKey,
    Dio? dio,
    TmdbDioFactory? dioFactory,
    TmdbProxyRecovery? recoverProxy,
    TmdbScrapeCache? cache,
  })  : _dioFactory = dioFactory ?? (dio == null ? _createDefaultDio : null),
        _recoverProxy = recoverProxy ??
            (dio == null ? ProxyManager.recoverOnlineResourceProxy : null),
        _cache = cache,
        _dio = dio ?? (dioFactory ?? _createDefaultDio)();

  static Dio _createDefaultDio() {
    final config = NetworkSettingsConfigFactory.create(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    );
    final dio = DioFactory.createForConfig(
      config,
      interceptors: const [],
    );
    dio.options.baseUrl = TmdbEndpointPolicy.primaryApiBaseUrl;
    return dio;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    final result = await searchPage(
      query,
      mediaType,
      language: language,
      page: 1,
    );
    return result.results;
  }

  @override
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
    required int page,
  }) async {
    _validateKey();
    if (page < 1) throw ArgumentError.value(page, 'page', '页码必须大于 0');
    final cache = _cache;
    if (cache != null) {
      return cache.getOrLoad<TmdbSearchPage>(
        _searchCacheKey(query, mediaType, language, page),
        () => _searchPageUncached(
          query,
          mediaType,
          language: language,
          page: page,
        ),
        kind: TmdbScrapeCacheKind.search,
      );
    }
    return _searchPageUncached(
      query,
      mediaType,
      language: language,
      page: page,
    );
  }

  Future<TmdbSearchPage> _searchPageUncached(
    String query,
    TmdbMediaType mediaType, {
    required String language,
    required int page,
  }) async {
    final response = await _withEndpointRecovery(
      (dio, baseUrl) => dio.get<Map<String, dynamic>>(
        '$baseUrl/search/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}',
        queryParameters: {
          ..._authenticationQuery,
          'query': query,
          'language': language,
          'include_adult': false,
          'page': page,
        },
        options: _authenticationOptions,
      ),
    );
    final results = response.data?['results'];
    final parsedPage = _asInt(response.data?['page']);
    final parsedTotalPages = _asInt(response.data?['total_pages']);
    return TmdbSearchPage(
      page: parsedPage > 0 ? parsedPage : page,
      totalPages: parsedTotalPages > 0 ? parsedTotalPages : page,
      results: results is! List
          ? const <TmdbMetadata>[]
          : results
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => _fromJson(
                  Map<String, dynamic>.from(item),
                  mediaType,
                  language,
                ),
              )
              .toList(growable: false),
    );
  }

  @override
  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    _validateKey();
    final cache = _cache;
    if (cache != null) {
      return cache.getOrLoad<List<String>>(
        _aliasCacheKey(id, mediaType, language),
        () => _alternativeTitlesUncached(id, mediaType, language: language),
        kind: TmdbScrapeCacheKind.aliases,
      );
    }
    return _alternativeTitlesUncached(id, mediaType, language: language);
  }

  Future<List<String>> _alternativeTitlesUncached(
    int id,
    TmdbMediaType mediaType, {
    required String language,
  }) async {
    final response = await _withEndpointRecovery(
      (dio, baseUrl) => dio.get<Map<String, dynamic>>(
        '$baseUrl/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}/$id/alternative_titles',
        queryParameters: <String, dynamic>{
          ..._authenticationQuery,
          'language': language,
        },
        options: _authenticationOptions,
      ),
    );
    final data = response.data;
    final rawTitles = data?['titles'] ?? data?['results'];
    if (rawTitles is! List) return const <String>[];
    final aliases = <String>[];
    for (final item in rawTitles.whereType<Map<Object?, Object?>>()) {
      final title = _asString(item['title']);
      if (title != null && !aliases.contains(title)) aliases.add(title);
    }
    return List<String>.unmodifiable(aliases);
  }

  @override
  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    _validateKey();
    final cache = _cache;
    if (cache != null) {
      return cache.getOrLoad<TmdbSeasonMetadata>(
        _seasonCacheKey(id, seasonNumber, language),
        () => _seasonDetailsUncached(id, seasonNumber, language: language),
        kind: TmdbScrapeCacheKind.details,
      );
    }
    return _seasonDetailsUncached(id, seasonNumber, language: language);
  }

  Future<TmdbSeasonMetadata> _seasonDetailsUncached(
    int id,
    int seasonNumber, {
    required String language,
  }) async {
    final primary = await _seasonDetailsForLanguage(
      id,
      seasonNumber,
      language,
    );
    if (language == 'en-US') return primary;
    try {
      final fallback = await _seasonDetailsForLanguage(
        id,
        seasonNumber,
        'en-US',
      );
      return _mergeSeasons(
        <TmdbSeasonMetadata>[primary],
        <TmdbSeasonMetadata>[fallback],
      ).single;
    } on Object {
      // 中文季度详情已经可用时，英文补充失败不能阻断刮削。
      return primary;
    }
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    _validateKey();
    final cache = _cache;
    if (cache != null) {
      return cache.getOrLoad<TmdbMetadata>(
        _detailsCacheKey(id, mediaType, language),
        () => _detailsUncached(id, mediaType, language: language),
        kind: TmdbScrapeCacheKind.details,
      );
    }
    return _detailsUncached(id, mediaType, language: language);
  }

  Future<TmdbMetadata> _detailsUncached(
    int id,
    TmdbMediaType mediaType, {
    required String language,
  }) async {
    final primary = await _detailsForLanguage(id, mediaType, language);
    if (language == 'en-US') {
      return primary;
    }
    TmdbMetadata fallback;
    try {
      // 中文详情可能缺少类型或季度字段，英文详情只作为补充来源。
      fallback = await _detailsForLanguage(id, mediaType, 'en-US');
    } on Object {
      // 中文详情已经可用时，英文补充失败不能阻断本地播放和刮削。
      return primary;
    }
    return primary.copyWith(
      aliases: _mergeStrings(primary.aliases, fallback.aliases),
      overview:
          _hasText(primary.overview) ? primary.overview : fallback.overview,
      posterUrl:
          _hasText(primary.posterUrl) ? primary.posterUrl : fallback.posterUrl,
      backdropUrl: _hasText(primary.backdropUrl)
          ? primary.backdropUrl
          : fallback.backdropUrl,
      genres: _mergeGenres(primary.genres, fallback.genres),
      seasons: _mergeSeasons(primary.seasons, fallback.seasons),
      popularity: primary.popularity ?? fallback.popularity,
      voteCount: primary.voteCount ?? fallback.voteCount,
    );
  }

  Future<TmdbSeasonMetadata> _seasonDetailsForLanguage(
    int id,
    int seasonNumber,
    String language,
  ) async {
    _validateKey();
    final response = await _withEndpointRecovery(
      (dio, baseUrl) => dio.get<Map<String, dynamic>>(
        '$baseUrl/tv/$id/season/$seasonNumber',
        queryParameters: <String, dynamic>{
          ..._authenticationQuery,
          'language': language,
        },
        options: _authenticationOptions,
      ),
    );
    return _seasonFromJson(
      response.data ?? const <String, dynamic>{},
      fallbackSeasonNumber: seasonNumber,
    );
  }

  Future<TmdbMetadata> _detailsForLanguage(
    int id,
    TmdbMediaType mediaType,
    String language,
  ) async {
    _validateKey();
    final response = await _withEndpointRecovery(
      (dio, baseUrl) => dio.get<Map<String, dynamic>>(
        '$baseUrl/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}/$id',
        queryParameters: {..._authenticationQuery, 'language': language},
        options: _authenticationOptions,
      ),
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
      popularity: _asDouble(json['popularity']),
      voteCount: _asNullableInt(json['vote_count']),
      posterUrl: _asString(json['poster_path']),
      backdropUrl: _asString(json['backdrop_path']),
      language: language,
      matchedAt: DateTime.now(),
      matchConfidence: 0,
      genres: _genreNames(json['genres']),
      seasons: _seasonsFromJson(json, mediaType),
    );
  }

  List<String> _genreNames(Object? value) {
    if (value is! List) return const <String>[];
    final result = <String>[];
    for (final raw in value.whereType<Map<Object?, Object?>>()) {
      final name = _asString(raw['name']);
      if (name != null && !result.contains(name)) result.add(name);
    }
    return List<String>.unmodifiable(result);
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

  TmdbSeasonMetadata _seasonFromJson(
    Map<String, dynamic> json, {
    int? fallbackSeasonNumber,
  }) {
    final episodes = _episodesFromJson(json['episodes']);
    final parsedSeasonNumber = _asInt(json['season_number']);
    final parsedEpisodeCount = _asInt(json['episode_count']);
    return TmdbSeasonMetadata(
      id: _asInt(json['id']),
      seasonNumber: parsedSeasonNumber > 0
          ? parsedSeasonNumber
          : fallbackSeasonNumber ?? parsedSeasonNumber,
      name: _asString(json['name']) ?? '',
      episodeCount:
          parsedEpisodeCount > 0 ? parsedEpisodeCount : episodes.length,
      overview: _asString(json['overview']),
      airDate: _asString(json['air_date']),
      posterUrl: _asString(json['poster_path']),
      episodes: episodes,
    );
  }

  List<TmdbEpisodeMetadata> _episodesFromJson(Object? value) {
    if (value is! List) return const <TmdbEpisodeMetadata>[];
    final episodes = value
        .whereType<Map<Object?, Object?>>()
        .map((raw) {
          final json = Map<String, dynamic>.from(raw);
          return TmdbEpisodeMetadata(
            id: _asInt(json['id']),
            episodeNumber: _asInt(json['episode_number']),
            name: _asString(json['name']) ?? '',
            overview: _asString(json['overview']),
            airDate: _asString(json['air_date']),
            stillUrl: _asString(json['still_path']),
            rating: _asDouble(json['vote_average']),
          );
        })
        .where((episode) => episode.episodeNumber > 0)
        .toList(growable: false)
      ..sort(
        (first, second) => first.episodeNumber.compareTo(second.episodeNumber),
      );
    return episodes;
  }

  List<TmdbSeasonMetadata> _mergeSeasons(
    List<TmdbSeasonMetadata> primary,
    List<TmdbSeasonMetadata> fallback,
  ) {
    final mergedByNumber = <int, TmdbSeasonMetadata>{
      for (final season in primary) season.seasonNumber: season,
    };
    for (final fallbackSeason in fallback) {
      final season = mergedByNumber[fallbackSeason.seasonNumber];
      if (season == null) {
        mergedByNumber[fallbackSeason.seasonNumber] = fallbackSeason;
        continue;
      }
      mergedByNumber[fallbackSeason.seasonNumber] = season.copyWith(
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
        episodes: _mergeEpisodes(
          season.episodes,
          fallbackSeason.episodes,
        ),
      );
    }
    final seasons = mergedByNumber.values.toList(growable: false)
      ..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
    return seasons;
  }

  List<TmdbEpisodeMetadata> _mergeEpisodes(
    List<TmdbEpisodeMetadata> primary,
    List<TmdbEpisodeMetadata> fallback,
  ) {
    final mergedByNumber = <int, TmdbEpisodeMetadata>{
      for (final episode in primary) episode.episodeNumber: episode,
    };
    for (final fallbackEpisode in fallback) {
      final episode = mergedByNumber[fallbackEpisode.episodeNumber];
      if (episode == null) {
        mergedByNumber[fallbackEpisode.episodeNumber] = fallbackEpisode;
        continue;
      }
      mergedByNumber[fallbackEpisode.episodeNumber] = episode.copyWith(
        name: _hasText(episode.name) ? episode.name : fallbackEpisode.name,
        overview: _hasText(episode.overview)
            ? episode.overview
            : fallbackEpisode.overview,
        airDate: _hasText(episode.airDate)
            ? episode.airDate
            : fallbackEpisode.airDate,
        stillUrl: _hasText(episode.stillUrl)
            ? episode.stillUrl
            : fallbackEpisode.stillUrl,
        rating: episode.rating ?? fallbackEpisode.rating,
      );
    }
    final episodes = mergedByNumber.values.toList(growable: false)
      ..sort(
        (first, second) => first.episodeNumber.compareTo(second.episodeNumber),
      );
    return episodes;
  }

  List<String> _mergeGenres(
    List<String> primary,
    List<String> fallback,
  ) {
    final result = <String>[];
    for (final genre in <String>[...primary, ...fallback]) {
      final normalized = genre.trim();
      if (normalized.isEmpty || result.contains(normalized)) continue;
      result.add(normalized);
    }
    return List<String>.unmodifiable(result);
  }

  List<String> _mergeStrings(List<String> primary, List<String> fallback) {
    final result = <String>[];
    for (final value in <String>[...primary, ...fallback]) {
      final normalized = value.trim();
      if (normalized.isEmpty || result.contains(normalized)) continue;
      result.add(normalized);
    }
    return List<String>.unmodifiable(result);
  }

  Future<T> _withEndpointRecovery<T>(
    Future<T> Function(Dio dio, String baseUrl) request,
  ) async {
    final firstBaseUrl = _preferredBaseUrl;
    try {
      return await request(_dio, firstBaseUrl);
    } on DioException catch (firstError) {
      if (!TmdbEndpointPolicy.canTryAnotherEndpoint(firstError)) rethrow;

      final secondBaseUrl = firstBaseUrl == TmdbEndpointPolicy.primaryApiBaseUrl
          ? TmdbEndpointPolicy.fallbackApiBaseUrl
          : TmdbEndpointPolicy.primaryApiBaseUrl;
      try {
        final result = await request(_dio, secondBaseUrl);
        _preferredBaseUrl = secondBaseUrl;
        AppLogger().i(
          'TMDB: 已切换官方端点 ${Uri.parse(secondBaseUrl).host}',
        );
        return result;
      } on DioException catch (secondError, secondStackTrace) {
        if (!TmdbEndpointPolicy.canTryAnotherEndpoint(secondError)) rethrow;

        final recoverProxy = _recoverProxy;
        final dioFactory = _dioFactory;
        if (recoverProxy == null || dioFactory == null) {
          Error.throwWithStackTrace(secondError, secondStackTrace);
        }

        bool recovered;
        try {
          recovered = await _recoverAndRebuild(recoverProxy, dioFactory);
        } catch (recoveryError, recoveryStackTrace) {
          AppLogger().w(
            'TMDB: 代理恢复失败',
            error: recoveryError,
            stackTrace: recoveryStackTrace,
          );
          Error.throwWithStackTrace(secondError, secondStackTrace);
        }
        if (!recovered) {
          Error.throwWithStackTrace(secondError, secondStackTrace);
        }
        _preferredBaseUrl = TmdbEndpointPolicy.primaryApiBaseUrl;
        return request(_dio, _preferredBaseUrl);
      }
    }
  }

  Future<bool> _recoverAndRebuild(
    TmdbProxyRecovery recoverProxy,
    TmdbDioFactory dioFactory,
  ) {
    final rebuildingDio = _rebuildingDio;
    if (rebuildingDio != null) return rebuildingDio;

    final task = _recoverAndRebuildOnce(recoverProxy, dioFactory);
    _rebuildingDio = task;
    return task.whenComplete(() {
      if (identical(_rebuildingDio, task)) {
        _rebuildingDio = null;
      }
    });
  }

  Future<bool> _recoverAndRebuildOnce(
    TmdbProxyRecovery recoverProxy,
    TmdbDioFactory dioFactory,
  ) async {
    if (!await recoverProxy()) return false;

    final previousDio = _dio;
    final replacementDio = dioFactory();
    _dio = replacementDio;
    if (!identical(previousDio, replacementDio)) {
      previousDio.close(force: true);
    }
    return true;
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

  int _asInt(Object? value) => value is num ? value.toInt() : 0;
  int? _asNullableInt(Object? value) => value is num ? value.toInt() : null;
  double? _asDouble(Object? value) => value is num ? value.toDouble() : null;
  String? _asString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _searchCacheKey(
    String query,
    TmdbMediaType mediaType,
    String language,
    int page,
  ) {
    return 'search|${mediaType.name}|$language|${_normalizeQuery(query)}|page:$page';
  }

  static String _aliasCacheKey(
    int id,
    TmdbMediaType mediaType,
    String language,
  ) {
    return 'alias|${mediaType.name}|$language|$id';
  }

  static String _seasonCacheKey(int id, int seasonNumber, String language) {
    return 'details|season|$language|$id|$seasonNumber';
  }

  static String _detailsCacheKey(
    int id,
    TmdbMediaType mediaType,
    String language,
  ) {
    return 'details|${mediaType.name}|$language|$id';
  }

  static String _normalizeQuery(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
