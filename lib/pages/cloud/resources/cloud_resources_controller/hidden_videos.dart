part of '../cloud_resources_controller.dart';

/// 隐藏视频：按来源隐藏/恢复视频与媒体库分集。
mixin _CloudHiddenVideosMixin on _CloudResourcesControllerBase {
  final Lock _hiddenVideoMutationLock = Lock();

  Future<void> hideVideos(Iterable<CloudFileEntry> videos) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final additions = [
      for (final video in videos)
        CloudHiddenVideo.fromEntry(sourceId: source.id, entry: video),
    ];
    await _updateHiddenVideos(
      source.id,
      (current) => <String, CloudHiddenVideo>{
        for (final record in current) record.identityKey: record,
        for (final record in additions) record.identityKey: record,
      }.values.toList(growable: false),
    );
  }

  Future<void> hideMediaLibraryEpisodes(
    Iterable<MediaLibraryEpisode> episodes,
  ) async {
    final bySource = <String, List<MediaLibraryEpisode>>{};
    for (final episode in episodes) {
      if (episode.sourceKind != MediaSourceKind.cloud ||
          episode.remoteId == null ||
          episode.remotePath == null) {
        throw ArgumentError.value(
          episode,
          'episodes',
          '隐藏项必须是有效的网盘视频',
        );
      }
      bySource.putIfAbsent(episode.sourceId, () => <MediaLibraryEpisode>[]).add(
            episode,
          );
    }
    for (final entry in bySource.entries) {
      await _updateHiddenVideos(entry.key, (current) {
        final records = <String, CloudHiddenVideo>{
          for (final record in current) record.identityKey: record,
        };
        for (final episode in entry.value) {
          final record = CloudHiddenVideo(
            sourceId: entry.key,
            remoteId: episode.remoteId!,
            remotePath: normalizeCloudHiddenVideoPath(episode.remotePath!),
            fileName: episode.name,
          );
          records[record.identityKey] = record;
        }
        return records.values.toList(growable: false);
      });
    }
  }

  Future<void> restoreHiddenVideo(CloudHiddenVideo record) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    if (record.sourceId != source.id) {
      throw ArgumentError.value(record, 'record', '隐藏视频不属于当前网盘来源');
    }
    await _updateHiddenVideos(
      source.id,
      (current) => current
          .where((candidate) => candidate.identityKey != record.identityKey)
          .toList(growable: false),
    );
  }

  Future<void> restoreAllHiddenVideos() async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    await _updateHiddenVideos(source.id, (_) => <CloudHiddenVideo>[]);
  }

  Future<void> _updateHiddenVideos(
    String sourceId,
    List<CloudHiddenVideo> Function(List<CloudHiddenVideo>) update,
  ) =>
      _hiddenVideoMutationLock.synchronized(() async {
        if (_disposed) return;
        // 跨页读改写串行执行，每次以持久化记录为准，写入失败不修改可见状态。
        final current = await _hiddenVideoRepository.getBySource(sourceId);
        final next = update(current);
        if (!_sameHiddenVideos(current, next)) {
          await _hiddenVideoRepository.replaceSource(sourceId, next);
        }
        if (!_disposed && selectedSource?.id == sourceId) {
          _hiddenVideos = next;
          _hiddenVideosRevision++;
          _invalidateCollection();
          _notify();
        }
        if (!_disposed) await reloadMediaLibrarySnapshot(force: true);
      });

  @override
  bool _isHiddenEntry(CloudFileEntry entry) {
    final source = selectedSource;
    if (source == null) return false;
    return _isHidden(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
    );
  }

  @override
  bool _isHidden({
    required String sourceId,
    required String remoteId,
    required String remotePath,
  }) =>
      _hiddenVideos.any(
        (record) => record.matches(
          sourceId: sourceId,
          remoteId: remoteId,
          remotePath: remotePath,
        ),
      );
}
