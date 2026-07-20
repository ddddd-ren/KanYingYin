import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

typedef CloudResourceSubtitleResolver = CloudRemoteRef? Function(
  CloudFileEntry video,
);

class CloudResourcePlaybackRequest {
  CloudResourcePlaybackRequest({
    required this.seriesTitle,
    required List<CloudPlaybackTarget> targets,
    required this.selectedStableId,
  }) : targets = List<CloudPlaybackTarget>.unmodifiable(targets);

  final String seriesTitle;
  final List<CloudPlaybackTarget> targets;
  final String selectedStableId;
}

CloudResourcePlaybackRequest buildCloudResourcePlaybackRequest({
  required String sourceId,
  required CloudResourceMediaGroup group,
  required CloudFileEntry selected,
  required CloudResourceSubtitleResolver subtitleFor,
}) {
  List<CloudFileEntry>? seasonVideos;
  for (final season in group.seasons) {
    if (season.videos.any((video) => _sameEntry(video, selected))) {
      seasonVideos = season.videos;
      break;
    }
  }
  final videos = seasonVideos ?? group.videos;
  final targets = videos.map((video) {
    final subtitle = subtitleFor(video);
    return CloudPlaybackTarget(
      sourceId: sourceId,
      remoteId: video.id,
      remotePath: video.remotePath,
      stableId: '$sourceId:${video.id}:${video.remotePath}',
      title: video.name,
      subtitleRemoteId: subtitle?.id,
      subtitleRemotePath: subtitle?.path,
    );
  }).toList(growable: false);
  final selectedTargets = targets
      .where(
        (target) =>
            target.remoteId == selected.id &&
            target.remotePath == selected.remotePath,
      )
      .toList(growable: false);
  if (selectedTargets.length != 1) {
    throw ArgumentError('选中的网盘视频不在播放列表中');
  }
  return CloudResourcePlaybackRequest(
    seriesTitle: group.displayName,
    targets: targets,
    selectedStableId: selectedTargets.single.stableId,
  );
}

bool _sameEntry(CloudFileEntry first, CloudFileEntry second) =>
    first.id == second.id && first.remotePath == second.remotePath;
