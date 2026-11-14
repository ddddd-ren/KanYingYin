import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';

class MediaLibraryQuery {
  const MediaLibraryQuery();

  bool matchesTitles(Iterable<String?> titles, String keyword) {
    final query = keyword.trim().toLowerCase();
    return query.isEmpty ||
        titles.any((title) => title?.toLowerCase().contains(query) == true);
  }

  bool matchesSeries(MediaLibrarySeries series, String keyword) =>
      _matchesNormalizedSeries(series, keyword.trim().toLowerCase());

  bool _contains(String? title, String query) =>
      title?.toLowerCase().contains(query) == true;

  bool _matchesMetadata(TmdbMetadata? metadata, String query) =>
      metadata != null &&
      (_contains(metadata.title, query) ||
          _contains(metadata.originalTitle, query) ||
          metadata.aliases.any((title) => _contains(title, query)));

  bool _matchesNormalizedSeries(MediaLibrarySeries series, String query) {
    if (query.isEmpty ||
        _contains(series.title, query) ||
        _contains(series.sourceName, query) ||
        series.legacySeriesTitles.any((title) => _contains(title, query)) ||
        _contains(series.tmdbTitle, query) ||
        _matchesMetadata(series.tmdbMetadata, query)) {
      return true;
    }
    for (final episode in series.episodes) {
      if (_contains(episode.name, query) ||
          _contains(episode.tmdbTitle, query) ||
          _contains(episode.tmdbOriginalTitle, query)) {
        return true;
      }
      final local = episode.localItem;
      if (local == null) continue;
      if ((local.name != episode.name && _contains(local.name, query)) ||
          (local.seriesName != series.title &&
              _contains(local.seriesName, query)) ||
          local.originalNames.any((title) => _contains(title, query)) ||
          (!identical(local.tmdb, series.tmdbMetadata) &&
              _matchesMetadata(local.tmdb, query))) {
        return true;
      }
    }
    return false;
  }

  List<MediaLibrarySeries> apply({
    required Iterable<MediaLibrarySeries> series,
    String sourceId = 'all',
    String keyword = '',
    Set<String> selectedGenres = const <String>{},
    Set<String> selectedCategories = const <String>{},
    Set<String> selectedCustomTags = const <String>{},
    Set<String> selectedTags = const <String>{},
    Map<String, Iterable<String>> extraTagsBySeries =
        const <String, Iterable<String>>{},
    Map<String, MediaLibraryUserState> userStates =
        const <String, MediaLibraryUserState>{},
    bool favoriteOnly = false,
    bool watchLaterOnly = false,
    String selectedCollection = '',
    Map<String, MediaWatchState> watchStates = const {},
    bool? watched,
    MediaClassificationMode classificationMode =
        MediaClassificationMode.conservative,
  }) {
    final query = keyword.trim().toLowerCase();
    final collection = selectedCollection.trim().toLowerCase();
    return series.where((item) {
      if (watched != null && mediaSeriesWatched(item, watchStates) != watched) {
        return false;
      }
      final userState = userStates[item.key];
      if (favoriteOnly && userState?.favorite != true) return false;
      if (watchLaterOnly && userState?.watchLater != true) return false;
      if (collection.isNotEmpty &&
          !(userState?.collections.any(
                (value) => value.toLowerCase() == collection,
              ) ??
              false)) {
        return false;
      }
      if (sourceId != 'all' && item.sourceId != sourceId) return false;
      if (query.isNotEmpty && !_matchesNormalizedSeries(item, query)) {
        return false;
      }
      if (selectedGenres.isNotEmpty &&
          !genresForSeries(item, state: userState, mode: classificationMode)
              .any(selectedGenres.contains)) {
        return false;
      }
      if (selectedCategories.isNotEmpty &&
          !categoriesForSeries(item, state: userState, mode: classificationMode)
              .any(selectedCategories.contains)) {
        return false;
      }
      if (selectedCustomTags.isNotEmpty &&
          !(extraTagsBySeries[item.seriesKey] ?? const <String>[])
              .any(selectedCustomTags.contains)) {
        return false;
      }
      if (selectedTags.isNotEmpty &&
          !tagsForSeries(item,
                  extraTags: extraTagsBySeries,
                  state: userState,
                  mode: classificationMode)
              .any(selectedTags.contains)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<String> availableGenres(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, MediaLibraryUserState> userStates = const {},
    MediaClassificationMode classificationMode =
        MediaClassificationMode.conservative,
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(genresForSeries(item,
            state: userStates[item.key], mode: classificationMode));
      }
    }
    return values.toList(growable: false)..sort();
  }

  Set<String> retainAvailableGenres(
    Set<String> selected,
    Iterable<String> available,
  ) {
    return selected.intersection(available.toSet());
  }

  List<String> availableTags(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, Iterable<String>> extraTagsBySeries =
        const <String, Iterable<String>>{},
    Map<String, MediaLibraryUserState> userStates = const {},
    MediaClassificationMode classificationMode =
        MediaClassificationMode.conservative,
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(tagsForSeries(item,
            extraTags: extraTagsBySeries,
            state: userStates[item.key],
            mode: classificationMode));
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> availableCategories(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, MediaLibraryUserState> userStates = const {},
    MediaClassificationMode classificationMode =
        MediaClassificationMode.conservative,
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(categoriesForSeries(item,
            state: userStates[item.key], mode: classificationMode));
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> availableCustomTags(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, Iterable<String>> customTagsBySeries =
        const <String, Iterable<String>>{},
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(customTagsBySeries[item.seriesKey] ?? const <String>[]);
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> availableCollections(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, MediaLibraryUserState> userStates =
        const <String, MediaLibraryUserState>{},
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(userStates[item.key]?.collections ?? const <String>[]);
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> tagsForSeries(
    MediaLibrarySeries item, {
    Map<String, Iterable<String>> extraTags =
        const <String, Iterable<String>>{},
    MediaLibraryUserState? state,
    MediaClassificationMode mode = MediaClassificationMode.conservative,
  }) {
    final classification = const MediaClassificationResolver()
        .resolve(item, state: state, mode: mode);
    final values = <String>{
      ...classification.genres,
      ...classification.categories,
      ...(extraTags[item.seriesKey] ?? const <String>[]),
    };
    values.removeWhere((value) => value.trim().isEmpty);
    return values.toList(growable: false);
  }

  List<String> genresForSeries(
    MediaLibrarySeries item, {
    MediaLibraryUserState? state,
    MediaClassificationMode mode = MediaClassificationMode.conservative,
  }) {
    return const MediaClassificationResolver()
        .resolve(item, state: state, mode: mode)
        .genres;
  }

  List<String> categoriesForSeries(
    MediaLibrarySeries item, {
    MediaLibraryUserState? state,
    MediaClassificationMode mode = MediaClassificationMode.conservative,
  }) {
    return const MediaClassificationResolver()
        .resolve(item, state: state, mode: mode)
        .categories;
  }
}
