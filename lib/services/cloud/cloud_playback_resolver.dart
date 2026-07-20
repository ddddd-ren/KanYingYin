import 'dart:io';

import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/cloud_subtitle_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_relay_service.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';
import 'package:path/path.dart' as p;

typedef CloudPlaybackClientFactory = CloudDriveClient Function(
  CloudSource source,
  CloudCredentialStore credentialStore,
  bool allowSelfSignedCertificate,
);

class CloudPlaybackTarget {
  const CloudPlaybackTarget({
    required this.sourceId,
    this.remoteId = '',
    required this.remotePath,
    required this.stableId,
    required this.title,
    this.subtitleRemotePath,
    this.subtitleRemoteId,
  });

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final String stableId;
  final String title;
  final String? subtitleRemotePath;
  final String? subtitleRemoteId;

  String get subtitleOffsetKey => cloudSubtitleOffsetKey(sourceId, remotePath);
}

class CloudResolvedPlayback {
  const CloudResolvedPlayback({
    required this.target,
    required this.videoUrl,
    required this.httpHeaders,
    this.subtitlePath,
    this.networkRoute = PlaybackNetworkRoute.inheritProxy,
    this.cloudProviderName,
    this.transport = CloudPlaybackTransport.direct,
    this.lease,
    this.totalBytes,
  });

  final CloudPlaybackTarget target;
  final String videoUrl;
  final Map<String, String> httpHeaders;
  final String? subtitlePath;
  final PlaybackNetworkRoute networkRoute;
  final String? cloudProviderName;
  final CloudPlaybackTransport transport;
  final CloudPlaybackLease? lease;
  final int? totalBytes;
}

class CloudPlaybackHttpException implements Exception {
  const CloudPlaybackHttpException(this.statusCode);

  final int statusCode;
}

bool shouldRefreshCloudLink(Object error) {
  if (error is CloudPlaybackHttpException) {
    return error.statusCode == 401 ||
        error.statusCode == 403 ||
        error.statusCode == 412;
  }
  if (error is String) {
    return RegExp(
          r'\b(?:http status|http error|status code)\s*[:=]?\s*(?:401|403|412)\b',
          caseSensitive: false,
        ).hasMatch(error) ||
        RegExp(
          r'\bfailed to open\b',
          caseSensitive: false,
        ).hasMatch(error) ||
        RegExp(
          r'\b(?:expiredlink|expired link|signature expired)\b',
          caseSensitive: false,
        ).hasMatch(error);
  }
  return error is CloudDriveException &&
      (error.type == CloudDriveErrorType.authentication ||
          error.type == CloudDriveErrorType.permission ||
          error.type == CloudDriveErrorType.expiredLink);
}

class CloudLinkRefreshGuard {
  bool _used = false;

  bool tryAcquire(Object error) {
    if (_used || !shouldRefreshCloudLink(error)) return false;
    _used = true;
    return true;
  }

  void reset() => _used = false;
}

class CloudPlaybackSessionToken {
  const CloudPlaybackSessionToken(this.generation);
  final int generation;
}

class CloudPlaybackRequestToken {
  const CloudPlaybackRequestToken(this.sessionGeneration, this.requestId);
  final int sessionGeneration;
  final int requestId;
}

class CloudPlaybackOperationCoordinator {
  int _sessionGeneration = 0;
  int _requestId = 0;

  CloudPlaybackSessionToken beginSession() {
    _sessionGeneration++;
    _requestId = 0;
    return CloudPlaybackSessionToken(_sessionGeneration);
  }

  CloudPlaybackRequestToken beginRequest(CloudPlaybackSessionToken session) {
    if (session.generation != _sessionGeneration) {
      return CloudPlaybackRequestToken(session.generation, -1);
    }
    return CloudPlaybackRequestToken(session.generation, ++_requestId);
  }

  bool isCurrent(CloudPlaybackRequestToken request) =>
      request.sessionGeneration == _sessionGeneration &&
      request.requestId == _requestId;
}

class CloudPlaybackNavigationCoordinator {
  int _generation = 0;
  bool _busy = false;

  int? tryBegin() {
    if (_busy) return null;
    _busy = true;
    return ++_generation;
  }

  bool isCurrent(int generation) => _busy && generation == _generation;

  void finish(int generation) {
    if (generation == _generation) _busy = false;
  }
}

class PlayerMediaToken {
  const PlayerMediaToken(this.generation, this.stableKey);
  final int generation;
  final String? stableKey;
}

class PlayerLifecycleToken {
  const PlayerLifecycleToken(this.generation);
  final int generation;
}

class PlayerLifecycleCoordinator {
  int _generation = 0;
  bool _active = false;

  PlayerLifecycleToken activate() {
    _active = true;
    return PlayerLifecycleToken(++_generation);
  }

  void invalidate() {
    _active = false;
    _generation++;
  }

  bool isCurrent(PlayerLifecycleToken token) =>
      _active && token.generation == _generation;
}

class PlayerMediaOperationCoordinator {
  int _generation = 0;
  bool _refreshing = false;
  final CloudLinkRefreshGuard _refreshGuard = CloudLinkRefreshGuard();

  PlayerMediaToken beginMedia(
    String? stableKey, {
    bool preserveRefreshState = false,
  }) {
    _generation++;
    if (!preserveRefreshState) {
      _refreshing = false;
      _refreshGuard.reset();
    }
    return PlayerMediaToken(_generation, stableKey);
  }

  bool isCurrent(PlayerMediaToken token) => token.generation == _generation;

  void invalidate() {
    _generation++;
    _refreshing = false;
  }

  bool tryBeginRefresh(PlayerMediaToken token, Object error) {
    if (!isCurrent(token) || _refreshing) return false;
    if (!_refreshGuard.tryAcquire(error)) return false;
    _refreshing = true;
    return true;
  }

  void finishRefresh(PlayerMediaToken token) {
    if (isCurrent(token)) _refreshing = false;
  }
}

String sanitizeMediaDescription(
  String value, {
  required bool isLocalPlayback,
}) {
  if (isLocalPlayback) {
    final normalized = value.replaceAll('\\', '/');
    final name = p.posix.basename(normalized);
    return name.isEmpty ? '本地文件' : name;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '远程媒体';
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

final RegExp _remoteMediaUriPattern = RegExp(
  "(?:https?|ftp|rtsp|rtmp)://[^\\s<>\\[\\]{}()\"']+",
  caseSensitive: false,
);

String sanitizeMediaDiagnosticText(
  String value, {
  required bool isLocalPlayback,
}) {
  if (isLocalPlayback) return value;
  return value.replaceAllMapped(_remoteMediaUriPattern, (match) {
    return sanitizeMediaDescription(
      match.group(0)!,
      isLocalPlayback: false,
    );
  });
}

String cloudSubtitleOffsetKey(String sourceId, String remotePath) {
  final normalized =
      p.posix.normalize(remotePath.replaceAll('\\', '/')).toLowerCase();
  return 'cloud:$sourceId:$normalized';
}

class CloudPlaybackResolver {
  CloudPlaybackResolver({
    CloudSourceRepository? sourceRepository,
    CloudCredentialStore? credentialStore,
    CloudPlaybackClientFactory? clientFactory,
    CloudProviderRegistry? providerRegistry,
    CloudSubtitleCache? subtitleCache,
    QuarkRangeRelayStarter? relayStarter,
  })  : _sourceRepository = sourceRepository ?? CloudSourceRepository(),
        _credentialStore = credentialStore ?? SecureCloudCredentialStore(),
        _providerRegistry = providerRegistry ??
            CloudProviderRegistry(
              clientFactories: clientFactory == null
                  ? const <CloudSourceType, CloudProviderClientFactory>{}
                  : <CloudSourceType, CloudProviderClientFactory>{
                      for (final type in CloudSourceType.values)
                        type: clientFactory,
                    },
            ),
        _subtitleCache =
            subtitleCache ?? CloudSubtitleCache(downloader: _downloadResource),
        _relayStarter = relayStarter ?? QuarkRangeRelayService().start;

  final CloudSourceRepository _sourceRepository;
  final CloudCredentialStore _credentialStore;
  final CloudProviderRegistry _providerRegistry;
  final CloudSubtitleCache? _subtitleCache;
  final QuarkRangeRelayStarter _relayStarter;

  Future<CloudResolvedPlayback> resolve(CloudPlaybackTarget target) async {
    final source = await _sourceRepository.getById(target.sourceId);
    if (source == null || !source.enabled) {
      throw StateError('网盘来源不存在或已停用');
    }
    CloudDriveClient? client;
    try {
      client = _providerRegistry.createClient(source, _credentialStore);
      final resource = await client.resolvePlayback(CloudRemoteRef(
        id: target.remoteId.isEmpty ? target.remotePath : target.remoteId,
        path: target.remotePath,
      ));
      String? subtitlePath;
      final subtitleRemotePath = target.subtitleRemotePath;
      if (_subtitleCache != null && subtitleRemotePath != null) {
        try {
          final subtitle = await client.getFile(CloudRemoteRef(
            id: target.subtitleRemoteId ?? subtitleRemotePath,
            path: subtitleRemotePath,
          ));
          subtitlePath = await _subtitleCache.cacheBeforePlayback(
            sourceId: source.id,
            subtitle: subtitle,
            client: client,
          );
        } on Object {
          subtitlePath = null;
        }
      }
      var videoUri = resource.uri;
      var httpHeaders = Map<String, String>.unmodifiable(resource.headers);
      var networkRoute = resource.networkRoute;
      var transport = source.type == CloudSourceType.quark
          ? resource.transport
          : CloudPlaybackTransport.direct;
      CloudPlaybackLease? lease;
      int? totalBytes;
      if (transport == CloudPlaybackTransport.quarkRangeRelay) {
        try {
          final relay = await _relayStarter(
            resource: _toQuarkRemoteResource(resource),
            refreshResource: () => _refreshQuarkResource(source.id, target),
          );
          videoUri = relay.uri;
          httpHeaders = const <String, String>{};
          networkRoute = PlaybackNetworkRoute.direct;
          lease = relay.lease;
          totalBytes = relay.totalLength;
        } on Object {
          if (!const QuarkRequestPolicy()
              .isTrustedOriginalDownloadUri(resource.uri)) {
            rethrow;
          }
          transport = CloudPlaybackTransport.direct;
        }
      }
      return CloudResolvedPlayback(
        target: target,
        videoUrl: videoUri.toString(),
        httpHeaders: httpHeaders,
        subtitlePath: subtitlePath,
        networkRoute: networkRoute,
        transport: transport,
        lease: lease,
        totalBytes: totalBytes,
        cloudProviderName: switch (source.type) {
          CloudSourceType.quark => '夸克',
          CloudSourceType.baidu => '百度网盘',
          CloudSourceType.openList => 'OpenList',
        },
      );
    } finally {
      await client?.close();
    }
  }

  Future<QuarkRemoteResource> _refreshQuarkResource(
    String sourceId,
    CloudPlaybackTarget target,
  ) async {
    final source = await _sourceRepository.getById(sourceId);
    if (source == null ||
        !source.enabled ||
        source.type != CloudSourceType.quark) {
      throw StateError('夸克网盘来源不存在或已停用');
    }
    final client = _providerRegistry.createClient(source, _credentialStore);
    try {
      final resource = await client.resolvePlayback(_remoteRef(target));
      if (resource.transport != CloudPlaybackTransport.quarkRangeRelay) {
        throw const QuarkRemoteProtocolException('刷新后未返回夸克原文件地址');
      }
      return _toQuarkRemoteResource(resource);
    } finally {
      await client.close();
    }
  }

  CloudRemoteRef _remoteRef(CloudPlaybackTarget target) => CloudRemoteRef(
        id: target.remoteId.isEmpty ? target.remotePath : target.remoteId,
        path: target.remotePath,
      );

  QuarkRemoteResource _toQuarkRemoteResource(CloudPlaybackResource resource) =>
      QuarkRemoteResource(
        uri: resource.uri,
        headers: resource.headers,
      );

  static Future<List<int>> _downloadResource(
    CloudPlaybackResource resource,
  ) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(resource.uri);
      resource.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw CloudPlaybackHttpException(response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '字幕下载失败，HTTP ${response.statusCode}',
          uri: resource.uri,
        );
      }
      return response.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
    } finally {
      httpClient.close(force: true);
    }
  }
}
