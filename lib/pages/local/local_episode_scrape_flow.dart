import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/tmdb_scrape_options_sheet.dart';
import 'package:kanyingyin/pages/tmdb_match_dialog.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';

Future<void> scrapeLocalEpisode({
  required BuildContext context,
  required LocalController controller,
  required LocalMediaIndexItem episode,
}) async {
  final options = await showModalBottomSheet<TmdbScrapeOptions>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TmdbScrapeOptionsSheet(
      initialOptions: controller.tmdbScrapeOptions,
    ),
  );
  if (options == null || !context.mounted) return;

  final result = await controller.scrapeEpisodeWithTmdb(
    episode.id,
    force: true,
    options: options,
  );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (result.status == TmdbScrapeStatus.matched) {
    messenger.showSnackBar(SnackBar(
      content: Text(result.posterDownloadFailures > 0
          ? '此集 TMDB 信息已更新，封面下载失败'
          : result.isolatedItemIds.isEmpty
              ? '此集 TMDB 信息已更新'
              : '此集已更新，其他人工确认剧集未修改'),
    ));
    return;
  }
  if (result.status == TmdbScrapeStatus.none) {
    messenger.showSnackBar(
      const SnackBar(content: Text('请先在设置中填写 TMDB API Key')),
    );
    return;
  }
  if (result.status == TmdbScrapeStatus.pending) {
    messenger.showSnackBar(const SnackBar(
      content: Text('此集未能自动确认，请使用“手动匹配此集”'),
    ));
    return;
  }
  messenger.showSnackBar(const SnackBar(content: Text('此集 TMDB 刮削失败')));
}

Future<void> openLocalEpisodeTmdbDialog({
  required BuildContext context,
  required LocalController controller,
  required LocalMediaIndexItem episode,
  bool reassignSeriesName = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final draft = controller.localTmdbDraftForPaths(
      originalName: episode.name,
      paths: <String>[episode.path],
    );
    final selected = await showDialog<TmdbScrapeResult>(
      context: context,
      builder: (_) => TmdbMatchDialog<TmdbScrapeResult>(
        title: reassignSeriesName ? '更正此集归属' : '手动匹配此集',
        safetyText: '仅更新看影音中的此集资料，不会修改本地文件',
        draft: draft,
        initialOptions: controller.tmdbScrapeOptions,
        onSearch: (request) => controller.searchLocalTmdbItem(
          episode.id,
          TmdbPreparedSearchRequest(
            queryTitle: request.queryTitle,
            queryYear: request.queryYear,
            mediaTypeMode: request.mediaTypeMode,
            options: request.options,
          ),
        ),
        onApply: (candidate, options) =>
            controller.selectTmdbCandidateForEpisode(
          episode.id,
          candidate.metadata,
          seriesNameOverride:
              reassignSeriesName ? candidate.metadata.title : null,
          options: options,
        ),
      ),
    );
    if (!context.mounted || selected == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(selected.posterDownloadFailures > 0
          ? '此集已保存匹配，封面下载失败'
          : reassignSeriesName
              ? '此集归属已更正'
              : '此集匹配已保存'),
    ));
  } on Object catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(_episodeScrapeError(error))));
  }
}

String _episodeScrapeError(Object error) {
  final message = error
      .toString()
      .replaceFirst(RegExp(r'^\w+(?:Error|Exception):\s*'), '')
      .trim();
  return message.isEmpty ? '此集 TMDB 操作失败' : message;
}
