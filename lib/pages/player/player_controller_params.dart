part of 'player_controller.dart';

class _PlayerInitializationCancelled implements Exception {
  const _PlayerInitializationCancelled();
}

class PlayerRuntimeSnapshot {
  const PlayerRuntimeSnapshot({
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.volume,
    required this.position,
    required this.buffer,
    required this.duration,
  });

  final bool playing;
  final bool buffering;
  final bool completed;
  final double volume;
  final Duration position;
  final Duration buffer;
  final Duration duration;
}

bool shouldApplyPlayerProxy({
  required bool proxyEnabled,
  required PlaybackNetworkRoute networkRoute,
}) =>
    proxyEnabled && networkRoute == PlaybackNetworkRoute.inheritProxy;

List<String>? resolveAnime4kShaderPaths({
  required String? directoryPath,
  required Anime4kAction action,
}) {
  if (directoryPath == null) return null;
  final names = switch (action) {
    Anime4kAction.enableEfficiency => mpvAnime4KShadersLite,
    Anime4kAction.enableQuality => mpvAnime4KShaders,
    Anime4kAction.clear => const <String>[],
  };
  return names
      .map((name) => p.join(directoryPath, name))
      .toList(growable: false);
}

String cloudPlaybackFailureMessage(String? providerName) {
  final label = providerName?.trim();
  return '${label == null || label.isEmpty ? '网盘' : label}播放地址不可用，请重新登录或稍后重试';
}

class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final int mediaId;
  final String sourceLabel;
  final int episode;
  final Map<String, String> httpHeaders;
  final String episodeTitle;
  final String referer;
  final int currentRoad;
  final String? coverUrl;
  final String? mediaTitle;
  final String? subtitlePath;
  final String? subtitleDisplayName;
  final String? subtitleStorageKey;
  final String? stableMediaKey;
  final PlaybackNetworkRoute networkRoute;
  final String? cloudProviderName;
  final CloudPlaybackTransport transport;
  final CloudPlaybackLease? lease;
  final int? totalBytes;
  final Future<PlaybackInitParams> Function()? refreshCloudPlayback;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.isLocalPlayback,
    required this.mediaId,
    required this.sourceLabel,
    required this.episode,
    required this.httpHeaders,
    required this.episodeTitle,
    required this.referer,
    required this.currentRoad,
    this.coverUrl,
    this.mediaTitle,
    this.subtitlePath,
    this.subtitleDisplayName,
    this.subtitleStorageKey,
    this.stableMediaKey,
    this.networkRoute = PlaybackNetworkRoute.inheritProxy,
    this.cloudProviderName,
    this.transport = CloudPlaybackTransport.direct,
    this.lease,
    this.totalBytes,
    this.refreshCloudPlayback,
  });

  PlaybackInitParams withOffset(int value) => PlaybackInitParams(
        videoUrl: videoUrl,
        offset: value,
        isLocalPlayback: isLocalPlayback,
        mediaId: mediaId,
        sourceLabel: sourceLabel,
        episode: episode,
        httpHeaders: httpHeaders,
        episodeTitle: episodeTitle,
        referer: referer,
        currentRoad: currentRoad,
        coverUrl: coverUrl,
        mediaTitle: mediaTitle,
        subtitlePath: subtitlePath,
        subtitleDisplayName: subtitleDisplayName,
        subtitleStorageKey: subtitleStorageKey,
        stableMediaKey: stableMediaKey,
        networkRoute: networkRoute,
        cloudProviderName: cloudProviderName,
        transport: transport,
        lease: lease,
        totalBytes: totalBytes,
        refreshCloudPlayback: refreshCloudPlayback,
      );
}

PlaybackInitParams mergeRefreshedCloudPlayback({
  required PlaybackInitParams previous,
  required PlaybackInitParams refreshed,
  required Duration position,
}) =>
    PlaybackInitParams(
      videoUrl: refreshed.videoUrl,
      offset: position.inSeconds,
      isLocalPlayback: refreshed.isLocalPlayback,
      mediaId: refreshed.mediaId,
      sourceLabel: refreshed.sourceLabel,
      episode: refreshed.episode,
      httpHeaders: refreshed.httpHeaders,
      episodeTitle: refreshed.episodeTitle,
      referer: refreshed.referer,
      currentRoad: refreshed.currentRoad,
      coverUrl: refreshed.coverUrl,
      mediaTitle: refreshed.mediaTitle,
      subtitlePath: refreshed.subtitlePath ?? previous.subtitlePath,
      subtitleDisplayName:
          refreshed.subtitleDisplayName ?? previous.subtitleDisplayName,
      subtitleStorageKey:
          refreshed.subtitleStorageKey ?? previous.subtitleStorageKey,
      stableMediaKey: refreshed.stableMediaKey ?? previous.stableMediaKey,
      networkRoute: refreshed.networkRoute,
      cloudProviderName:
          refreshed.cloudProviderName ?? previous.cloudProviderName,
      transport: refreshed.transport,
      lease: refreshed.lease,
      totalBytes: refreshed.totalBytes,
      refreshCloudPlayback:
          refreshed.refreshCloudPlayback ?? previous.refreshCloudPlayback,
    );

class CloudPlaybackRefreshTransaction {
  const CloudPlaybackRefreshTransaction({
    required this.previous,
    required this.position,
    required this.wasPlaying,
  });

  final PlaybackInitParams previous;
  final Duration position;
  final bool wasPlaying;

  bool get shouldPauseAfterRefresh => !wasPlaying;

  PlaybackInitParams merge(PlaybackInitParams refreshed) =>
      mergeRefreshedCloudPlayback(
        previous: previous,
        refreshed: refreshed,
        position: position,
      );
}
