import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

typedef ManualEpisodeDetailsLoader = Future<TmdbMetadata> Function(
  int id,
  TmdbMediaType mediaType,
  String language,
);
typedef ManualEpisodeSeasonLoader = Future<TmdbSeasonMetadata> Function(
  int id,
  int seasonNumber,
  String language,
);

final class ManualEpisodeMatchController extends ChangeNotifier {
  ManualEpisodeMatchController({
    required TmdbMetadata selectedSeries,
    required List<ManualEpisodeMatchItem> items,
    required ManualEpisodeDetailsLoader loadDetails,
    required ManualEpisodeSeasonLoader loadSeason,
  })  : _metadata = selectedSeries,
        _items = List<ManualEpisodeMatchItem>.unmodifiable(items),
        _loadDetails = loadDetails,
        _loadSeason = loadSeason;

  TmdbMetadata _metadata;
  final List<ManualEpisodeMatchItem> _items;
  final ManualEpisodeDetailsLoader _loadDetails;
  final ManualEpisodeSeasonLoader _loadSeason;
  final Map<int, TmdbSeasonMetadata> _loadedSeasons =
      <int, TmdbSeasonMetadata>{};
  final Map<String, ManualEpisodeAssignment> _assignments =
      <String, ManualEpisodeAssignment>{};

  bool loadingDetails = false;
  bool loadingSeason = false;
  String? operationError;
  int? selectedSeasonNumber;

  TmdbMetadata get metadata => _metadata;
  List<ManualEpisodeMatchItem> get items => _items;

  List<TmdbSeasonMetadata> get availableSeasons {
    final seasons = _metadata.seasons
        .where((season) => season.seasonNumber > 0)
        .toList(growable: false)
      ..sort(
          (first, second) => first.seasonNumber.compareTo(second.seasonNumber));
    return seasons;
  }

  List<TmdbEpisodeMetadata> get episodes {
    final seasonNumber = selectedSeasonNumber;
    if (seasonNumber == null) return const <TmdbEpisodeMetadata>[];
    return _loadedSeasons[seasonNumber]?.episodes ??
        const <TmdbEpisodeMetadata>[];
  }

  List<ManualEpisodeAssignment> get assignments =>
      List<ManualEpisodeAssignment>.unmodifiable(_assignments.values);

  bool get canComplete =>
      selectedSeasonNumber != null && episodes.isNotEmpty && !loadingSeason;

  ManualEpisodeAssignment? assignmentFor(String resourceId) {
    return _assignments[resourceId];
  }

  Future<void> initialize() async {
    if (_metadata.mediaType != TmdbMediaType.tv) {
      throw StateError('剧集匹配只支持 TMDB 电视剧');
    }
    loadingDetails = true;
    operationError = null;
    notifyListeners();
    try {
      final details = await _loadDetails(
        _metadata.id,
        TmdbMediaType.tv,
        _metadata.language,
      );
      if (details.mediaType != TmdbMediaType.tv) {
        throw StateError('TMDB 返回的作品不是电视剧');
      }
      _metadata = details;
    } on Object catch (error) {
      operationError = _errorMessage(error);
      rethrow;
    } finally {
      loadingDetails = false;
      notifyListeners();
    }
    final seasons = availableSeasons;
    if (seasons.length == 1) {
      await selectSeason(seasons.single.seasonNumber);
    }
  }

  Future<void> selectSeason(int seasonNumber) async {
    if (seasonNumber <= 0 ||
        !availableSeasons.any(
          (season) => season.seasonNumber == seasonNumber,
        )) {
      throw StateError('选择的季度不存在');
    }
    operationError = null;
    loadingSeason = true;
    notifyListeners();
    try {
      final season = _loadedSeasons[seasonNumber] ??
          await _loadSeason(
            _metadata.id,
            seasonNumber,
            _metadata.language,
          );
      if (season.seasonNumber != seasonNumber) {
        throw StateError('TMDB 返回了错误的季度资料');
      }
      _loadedSeasons[seasonNumber] = season;
      _metadata = _mergeSeason(_metadata, season);
      selectedSeasonNumber = seasonNumber;
      _applyInitialAssignments(season);
    } on Object catch (error) {
      operationError = _errorMessage(error);
      rethrow;
    } finally {
      loadingSeason = false;
      notifyListeners();
    }
  }

  void assignEpisode(String resourceId, int episodeNumber) {
    final seasonNumber = selectedSeasonNumber;
    if (seasonNumber == null ||
        !episodes.any((episode) => episode.episodeNumber == episodeNumber)) {
      throw StateError('选择的集不属于当前季度');
    }
    _requireItem(resourceId);
    _assignments[resourceId] = ManualEpisodeAssignment.mapped(
      resourceId: resourceId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    notifyListeners();
  }

  void keepOriginal(String resourceId) {
    _requireItem(resourceId);
    _assignments[resourceId] = ManualEpisodeAssignment.keepOriginal(resourceId);
    notifyListeners();
  }

  void restoreAutomatic(String resourceId) {
    _requireItem(resourceId);
    _assignments[resourceId] =
        ManualEpisodeAssignment.restoreAutomatic(resourceId);
    notifyListeners();
  }

  void clearAssignment(String resourceId) {
    _requireItem(resourceId);
    _assignments.remove(resourceId);
    notifyListeners();
  }

  void _applyInitialAssignments(TmdbSeasonMetadata season) {
    _assignments.clear();
    final validEpisodes =
        season.episodes.map((episode) => episode.episodeNumber).toSet();
    for (final item in _items) {
      if (item.manualOverride) {
        final episodeNumber = item.existingEpisodeNumber;
        if (item.existingSeasonNumber == season.seasonNumber &&
            episodeNumber != null &&
            validEpisodes.contains(episodeNumber)) {
          _assignments[item.resourceId] = ManualEpisodeAssignment.mapped(
            resourceId: item.resourceId,
            seasonNumber: season.seasonNumber,
            episodeNumber: episodeNumber,
          );
        } else {
          _assignments[item.resourceId] =
              ManualEpisodeAssignment.keepOriginal(item.resourceId);
        }
        continue;
      }
      final episodeNumber = item.automaticEpisodeNumber;
      if (item.automaticSeasonNumber == season.seasonNumber &&
          episodeNumber != null &&
          validEpisodes.contains(episodeNumber)) {
        _assignments[item.resourceId] = ManualEpisodeAssignment.mapped(
          resourceId: item.resourceId,
          seasonNumber: season.seasonNumber,
          episodeNumber: episodeNumber,
        );
      }
    }
  }

  void _requireItem(String resourceId) {
    if (!_items.any((item) => item.resourceId == resourceId)) {
      throw StateError('不存在的匹配资源：$resourceId');
    }
  }

  TmdbMetadata _mergeSeason(
    TmdbMetadata metadata,
    TmdbSeasonMetadata loaded,
  ) {
    final seasons = <TmdbSeasonMetadata>[
      for (final season in metadata.seasons)
        if (season.seasonNumber != loaded.seasonNumber) season,
      loaded,
    ]..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
    return metadata.copyWith(seasons: seasons);
  }

  String _errorMessage(Object error) {
    final text = error
        .toString()
        .replaceFirst(RegExp(r'^\w+(?:Error|Exception):\s*'), '');
    return text.trim().isEmpty ? 'TMDB 剧集资料加载失败' : text.trim();
  }
}
