import 'dart:io';

import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_subtitle_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';
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
  });

  final CloudPlaybackTarget target;
  final String videoUrl;
  final Map<String, String> httpHeaders;
  final String? subtitlePath;
}

class CloudPlaybackHttpException implements Exception {
  const CloudPlaybackHttpException(this.statusCode);

  final int statusCode;
}

bool shouldRefreshCloudLink(Object error) {
  if (error is CloudPlaybackHttpException) {
    return error.statusCode == 401 || error.statusCode == 403;
  }
  if (error is String) {
    return RegExp(
          r'\b(?:http status|http error|status code)\s*[:=]?\s*(?:401|403)\b',
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
    CloudSubtitleCache? subtitleCache,
  })  : _sourceRepository = sourceRepository ?? CloudSourceRepository(),
        _credentialStore = credentialStore ?? SecureCloudCredentialStore(),
        _clientFactory = clientFactory ?? _createClient,
        _subtitleCache =
            subtitleCache ?? CloudSubtitleCache(downloader: _downloadResource);

  final CloudSourceRepository _sourceRepository;
  final CloudCredentialStore _credentialStore;
  final CloudPlaybackClientFactory _clientFactory;
  final CloudSubtitleCache? _subtitleCache;

  Future<CloudResolvedPlayback> resolve(CloudPlaybackTarget target) async {
    final source = await _sourceRepository.getById(target.sourceId);
    if (source == null || !source.enabled) {
      throw StateError('网盘来源不存在或已停用');
    }
    CloudDriveClient? client;
    try {
      client = _clientFactory(
        source,
        _credentialStore,
        source.allowSelfSignedCertificate,
      );
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
      return CloudResolvedPlayback(
        target: target,
        videoUrl: resource.uri.toString(),
        httpHeaders: Map<String, String>.unmodifiable(resource.headers),
        subtitlePath: subtitlePath,
      );
    } finally {
      await client?.close();
    }
  }

  static CloudDriveClient _createClient(
    CloudSource source,
    CloudCredentialStore credentialStore,
    bool allowSelfSignedCertificate,
  ) =>
      switch (source.type) {
        CloudSourceType.openList => OpenListClient(
            source: source,
            credentialStore: credentialStore,
            allowSelfSignedCertificate: allowSelfSignedCertificate,
          ),
        CloudSourceType.quark => throw const CloudDriveException(
            CloudDriveErrorType.incompatible,
          ),
      };

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
