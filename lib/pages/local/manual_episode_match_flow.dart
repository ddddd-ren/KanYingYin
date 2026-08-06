import 'package:flutter/material.dart';
import 'package:kanyingyin/features/episode_matching/presentation/manual_episode_match_dialog.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/tmdb_match_dialog.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

Future<void> openLocalManualEpisodeMatch({
  required BuildContext context,
  required LocalController controller,
  required String originalName,
  required List<String> paths,
  String? seriesNameOverride,
  bool reassignSeriesName = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final seriesName = controller.indexedSeriesNameForPaths(paths);
    if (seriesName == null) {
      throw StateError('请先扫描媒体库，再进行剧集匹配');
    }
    final draft = controller.localTmdbDraftForPaths(
      originalName: originalName,
      paths: paths,
    );
    final selected = await showDialog<TmdbMetadata>(
      context: context,
      builder: (_) => TmdbMatchDialog<TmdbMetadata>(
        title: '选择 TMDB 电视剧',
        safetyText: '仅更新看影音中的资料，不会修改本地文件',
        draft: TmdbMatchDraft(
          originalName: draft.originalName,
          searchTitle: draft.searchTitle,
          mediaTypeMode: TmdbMediaTypeMode.tv,
          year: draft.year,
          seasonNumber: draft.seasonNumber,
          episodeNumber: draft.episodeNumber,
        ),
        initialOptions: controller.tmdbScrapeOptions.copyWith(
          mediaTypeMode: TmdbMediaTypeMode.tv,
        ),
        onSearch: (request) => controller.searchLocalTmdb(
          seriesName,
          TmdbPreparedSearchRequest(
            queryTitle: request.queryTitle,
            queryYear: request.queryYear,
            mediaTypeMode: TmdbMediaTypeMode.tv,
            options: request.options.copyWith(
              mediaTypeMode: TmdbMediaTypeMode.tv,
            ),
          ),
        ),
        onApply: (candidate, _) async {
          if (candidate.metadata.mediaType != TmdbMediaType.tv) {
            throw StateError('请选择电视剧作品');
          }
          return candidate.metadata;
        },
      ),
    );
    if (!context.mounted || selected == null) return;
    final matchController = controller.manualEpisodeMatchControllerForPaths(
      paths: paths,
      selectedSeries: selected,
    );
    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ManualEpisodeMatchDialog<void>(
        controller: matchController,
        onSave: (metadata, seasonNumber, assignments) async {
          await controller.saveManualEpisodeAssignments(
            paths: paths,
            assignments: assignments,
            metadata: metadata,
            selectedSeasonNumber: seasonNumber,
            seriesNameOverride:
                reassignSeriesName ? metadata.title : seriesNameOverride,
          );
          saved = true;
        },
      ),
    );
    if (!context.mounted || !saved) return;
    messenger.showSnackBar(const SnackBar(content: Text('剧集匹配已保存')));
  } on Object catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(_matchError(error))));
  }
}

String _matchError(Object error) {
  return error
      .toString()
      .replaceFirst(RegExp(r'^\w+(?:Error|Exception):\s*'), '')
      .trim();
}
