part of '../cloud_resources_controller.dart';

/// 隐藏视频：按来源隐藏/恢复视频与媒体库分集。
mixin _CloudHiddenVideosMixin on _CloudResourcesControllerBase {
  Future<void> hideVideos(Iterable<CloudFileEntry> videos) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final nextByIdentity = <String, CloudHiddenVideo>{
      for (final record in _hiddenVideos) record.identityKey: record,
    };
    for (final video in videos) {
      final record = CloudHiddenVideo.fromEntry(
        sourceId: source.id,
        entry: video,
      );
      nextByIdentity[record.identityKey] = record;
    }
    final next = nextByIdentity.values.toList(growable: false);
    if (_sameHiddenVideos(_hiddenVideos, next)) return;
    await _hiddenVideoRepository.replaceSource(source.id, next);
    if (selectedSource?.id != source.id) return;
    _hiddenVideos = next;
    _invalidateCollection();
    await reloadMediaLibrarySnapshot();
    _notify();
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
      final records = <String, CloudHiddenVideo>{
        for (final record
            in await _hiddenVideoRepository.getBySource(entry.key))
          record.identityKey: record,
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
      await _hiddenVideoRepository.replaceSource(
        entry.key,
        records.values.toList(growable: false),
      );
    }
    await reloadMediaLibrarySnapshot();
  }

  Future<void> restoreHiddenVideo(CloudHiddenVideo record) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    if (record.sourceId != source.id) {
      throw ArgumentError.value(record, 'record', '隐藏视频不属于当前网盘来源');
    }
    final next = _hiddenVideos
        .where((candidate) => candidate.identityKey != record.identityKey)
        .toList(growable: false);
    if (next.length == _hiddenVideos.length) return;
    await _hiddenVideoRepository.replaceSource(source.id, next);
    if (selectedSource?.id != source.id) return;
    _hiddenVideos = next;
    _invalidateCollection();
    await reloadMediaLibrarySnapshot();
    _notify();
  }

  Future<void> restoreAllHiddenVideos() async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    if (_hiddenVideos.isEmpty) return;
    await _hiddenVideoRepository.clearSource(source.id);
    if (selectedSource?.id != source.id) return;
    _hiddenVideos = <CloudHiddenVideo>[];
    _invalidateCollection();
    await reloadMediaLibrarySnapshot();
    _notify();
  }

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
