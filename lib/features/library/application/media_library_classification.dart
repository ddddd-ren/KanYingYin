import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

enum MediaClassificationMode {
  conservative,
  standard,
  manual;

  String get label => switch (this) {
        conservative => '保守',
        standard => '标准',
        manual => '全手动',
      };
}

enum MediaClassificationConfidence {
  high,
  medium,
  low;

  String get label => switch (this) {
        high => '高可信',
        medium => '中可信',
        low => '低可信',
      };
}

class MediaClassificationSuggestion {
  const MediaClassificationSuggestion({
    required this.label,
    required this.confidence,
    required this.reason,
  });

  final String label;
  final MediaClassificationConfidence confidence;
  final String reason;
}

class MediaClassificationResult {
  const MediaClassificationResult({
    required this.categories,
    required this.genres,
    required this.categorySuggestions,
    required this.genreSuggestions,
    required this.needsConfirmation,
    required this.isManual,
  });

  final List<String> categories;
  final List<String> genres;
  final List<MediaClassificationSuggestion> categorySuggestions;
  final List<MediaClassificationSuggestion> genreSuggestions;
  final bool needsConfirmation;
  final bool isManual;
}

class MediaClassificationResolver {
  const MediaClassificationResolver();

  MediaClassificationResult resolve(
    MediaLibrarySeries series, {
    MediaLibraryUserState? state,
    MediaClassificationMode mode = MediaClassificationMode.conservative,
  }) {
    final metadata = <TmdbMetadata>{
      if (series.tmdbMetadata case final value?) value,
      for (final episode in series.episodes)
        if (episode.localItem?.tmdb case final value?) value,
    };
    final genres = _normalized([
      ...series.genres,
      for (final value in metadata) ...value.genres,
    ]);
    final types = <TmdbMediaType>{
      if (series.mediaType case final value?) value,
      for (final value in metadata) value.mediaType,
    };
    final isAnimation = genres.any(_isAnimation);
    final hasEpisodeClue = series.episodes.any(
      (episode) =>
          episode.seasonNumber != null || episode.episodeNumber != null,
    );
    final inferredTv = types.isEmpty && !isAnimation && hasEpisodeClue;
    final categories = <String>[
      if (types.contains(TmdbMediaType.movie)) '电影',
      if (isAnimation) '动漫',
      if (!isAnimation && (types.contains(TmdbMediaType.tv) || inferredTv))
        '电视剧',
    ];
    final hasConflict = _hasConflict(series, metadata, types);
    var confidence = genres.isEmpty || inferredTv
        ? MediaClassificationConfidence.low
        : MediaClassificationConfidence.medium;
    if (metadata.isNotEmpty && genres.isNotEmpty && !inferredTv) {
      confidence = MediaClassificationConfidence.high;
      for (final value in metadata) {
        final current = _metadataConfidence(value);
        if (current.index > confidence.index) confidence = current;
      }
    }
    if (hasConflict) confidence = MediaClassificationConfidence.low;
    final reason = hasConflict
        ? '同一作品的 TMDB 身份、类型或题材存在冲突，需要人工确认'
        : inferredTv
            ? '仅有季集线索，不能确认作品分类'
            : genres.isEmpty
                ? '缺少题材证据，不能确认作品分类'
                : switch (confidence) {
                    MediaClassificationConfidence.high =>
                      'TMDB 类型与题材一致，资料匹配依据充分',
                    MediaClassificationConfidence.medium =>
                      '已有类型或题材记录，但完整匹配依据不足',
                    MediaClassificationConfidence.low =>
                      'TMDB 资料标识或匹配依据不足，需要人工确认',
                  };
    final categorySuggestions = <MediaClassificationSuggestion>[
      for (final category in categories)
        MediaClassificationSuggestion(
          label: category,
          confidence: confidence,
          reason: category == '动漫' ? '题材包含动画；$reason' : reason,
        ),
    ];
    const genreReason = '题材标签默认跟随 TMDB，不单独触发确认';
    final genreSuggestions = <MediaClassificationSuggestion>[
      for (final genre in genres)
        MediaClassificationSuggestion(
          label: genre,
          confidence: confidence,
          reason: genreReason,
        ),
    ];
    final categoryOverride = state?.categoryOverride;
    final genreOverride = state?.genreOverride;
    final selectedCategories = categoryOverride == null
        ? _automaticSelection(categorySuggestions, mode)
        : _normalized(categoryOverride);
    if (selectedCategories.any(
          (value) => !const ['电影', '动漫', '电视剧'].contains(value),
        ) ||
        (selectedCategories.contains('动漫') &&
            selectedCategories.contains('电视剧'))) {
      throw ArgumentError.value(
          categoryOverride, 'categoryOverride', '分类无效或相互冲突');
    }
    // 题材标签默认直接沿用 TMDB；只有用户明确保存了人工覆盖时才使用覆盖值。
    final selectedGenres =
        genreOverride == null ? genres : _normalized(genreOverride);
    return MediaClassificationResult(
      categories: List.unmodifiable(selectedCategories),
      genres: List.unmodifiable(selectedGenres),
      categorySuggestions: List.unmodifiable(categorySuggestions),
      genreSuggestions: List.unmodifiable(genreSuggestions),
      needsConfirmation: categoryOverride == null && selectedCategories.isEmpty,
      isManual: categoryOverride != null || genreOverride != null,
    );
  }

  bool _hasConflict(
    MediaLibrarySeries series,
    Set<TmdbMetadata> metadata,
    Set<TmdbMediaType> types,
  ) {
    if (types.length > 1 ||
        metadata.map((value) => value.id).toSet().length > 1) {
      return true;
    }
    final genreSets = [
      if (series.genres.isNotEmpty) _genreSet(series.genres),
      for (final value in metadata)
        if (value.genres.isNotEmpty) _genreSet(value.genres),
    ];
    return genreSets.any((genres) =>
        genres.length != genreSets.first.length ||
        !genres.containsAll(genreSets.first));
  }

  MediaClassificationConfidence _metadataConfidence(TmdbMetadata metadata) {
    final score = metadata.matchConfidence;
    if (metadata.id <= 0 ||
        metadata.title.trim().isEmpty ||
        _normalized(metadata.genres).isEmpty ||
        !score.isFinite ||
        score < 0.5 ||
        score > 1) {
      return MediaClassificationConfidence.low;
    }
    return score >= 0.8
        ? MediaClassificationConfidence.high
        : MediaClassificationConfidence.medium;
  }

  List<String> _automaticSelection(
    List<MediaClassificationSuggestion> suggestions,
    MediaClassificationMode mode,
  ) {
    if (mode == MediaClassificationMode.manual || suggestions.length != 1) {
      return const [];
    }
    final suggestion = suggestions.single;
    if (suggestion.confidence == MediaClassificationConfidence.high ||
        (mode == MediaClassificationMode.standard &&
            suggestion.confidence == MediaClassificationConfidence.medium)) {
      return [suggestion.label];
    }
    return const [];
  }

  List<String> _normalized(Iterable<String> values) {
    final identities = <String>{};
    return [
      for (final value in values.map((value) => value.trim()))
        if (value.isNotEmpty && identities.add(value.toLowerCase())) value,
    ];
  }

  Set<String> _genreSet(Iterable<String> values) =>
      _normalized(values).map((value) => value.toLowerCase()).toSet();

  bool _isAnimation(String value) =>
      const ['动画', '动漫', 'animation', 'anime'].contains(value.toLowerCase());
}
