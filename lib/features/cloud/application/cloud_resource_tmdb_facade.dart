import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

/// 构建网盘资源 TMDB 目标和匹配草稿，避免页面状态控制器重复识别规则。
class CloudResourceTmdbFacade {
  const CloudResourceTmdbFacade();

  CloudResourceTmdbTarget targetFor({
    required CloudSource source,
    required CloudFileEntry entry,
    CloudResourceTmdbRecord? record,
    CloudMediaIndexItem? indexed,
  }) {
    final indexedEpisode = indexed?.mediaType == CloudMediaType.episode;
    return CloudResourceTmdbTarget(
      sourceId: source.id,
      remote: CloudRemoteRef(id: entry.id, path: entry.remotePath),
      displayName: entry.name,
      resourceKind: entry.isDirectory
          ? CloudResourceKind.directory
          : CloudResourceKind.standaloneVideo,
      customTitle: record?.customTitle,
      matchingTitle: indexedEpisode ? indexed?.seriesName : null,
      matchingSeasonNumber: indexedEpisode ? indexed?.seasonNumber : null,
      matchingEpisodeNumber: indexedEpisode ? indexed?.episodeNumber : null,
      size: entry.isDirectory ? null : entry.size,
    );
  }

  TmdbMatchDraft draftFor({
    required CloudFileEntry entry,
    CloudResourceTmdbRecord? record,
    CloudMediaIndexItem? indexed,
  }) {
    final parsed = const CloudMediaNameParser().parse(
      originalName: entry.name,
      isDirectory: entry.isDirectory,
      preferredTitle: record?.customTitle ?? record?.title,
    );
    if (indexed == null || indexed.mediaType != CloudMediaType.episode) {
      return parsed;
    }
    final preferredTitle = record?.customTitle ?? record?.title;
    return TmdbMatchDraft(
      originalName: parsed.originalName,
      searchTitle: preferredTitle?.trim().isNotEmpty == true
          ? preferredTitle!.trim()
          : indexed.seriesName,
      mediaTypeMode: TmdbMediaTypeMode.tv,
      year: parsed.year,
      seasonNumber: indexed.seasonNumber ?? parsed.seasonNumber,
      episodeNumber: indexed.episodeNumber ?? parsed.episodeNumber,
    );
  }
}
