import 'dart:async';

import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';
import 'package:path/path.dart' as p;

typedef XunleiApiFactory = XunleiApi Function({
  required String deviceId,
  String? captchaToken,
});

class XunleiDriveClient implements CloudDriveClient {
  XunleiDriveClient({
    required CloudSource source,
    required CloudCredentialStore credentialStore,
    XunleiApiFactory? apiFactory,
    XunleiRequestPolicy requestPolicy = const XunleiRequestPolicy(),
  })  : _source = source,
        _credentialStore = credentialStore,
        _apiFactory = apiFactory ?? _createApi,
        _requestPolicy = requestPolicy;

  static const int _pageSize = 100;
  static const int _maxPages = 200;

  final CloudSource _source;
  final CloudCredentialStore _credentialStore;
  final XunleiApiFactory _apiFactory;
  final XunleiRequestPolicy _requestPolicy;
  XunleiApi? _api;
  Future<void>? _refreshing;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {
    if (source.type != CloudSourceType.xunlei) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    await _authenticateCredential(credential, replaceExisting: true);
  }

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    final api = await _ensureApi();
    final entries = <CloudFileEntry>[];
    final seenIds = <String>{};
    final seenPageTokens = <String>{};
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final result = await api.listDirectoryPage(
        directoryId: directory.path == '/' &&
                (directory.id == '0' || directory.id == '/')
            ? ''
            : directory.id,
        pageToken: pageToken,
        size: _pageSize,
      );
      for (final file in result.files) {
        if (!seenIds.add(file.id)) continue;
        entries.add(_toEntry(file, parentPath: directory.path));
      }
      final next = result.nextPageToken?.trim();
      if (next == null || next.isEmpty) {
        return List<CloudFileEntry>.unmodifiable(entries);
      }
      if (!seenPageTokens.add(next)) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      pageToken = next;
    }
    throw const CloudDriveException(CloudDriveErrorType.incompatible);
  }

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async {
    final detail = await (await _ensureApi()).fileDetail(file.id);
    return _toEntry(
      detail.file,
      parentPath: p.posix.dirname(file.path),
    );
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async {
    final detail = await (await _ensureApi()).fileDetail(file.id);
    if (!_requestPolicy.isTrustedDownloadUri(detail.originalUri)) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return CloudPlaybackResource(
      uri: detail.originalUri,
      headers: const <String, String>{
        'User-Agent': XunleiRequestPolicy.downloadUserAgent,
      },
      networkRoute: PlaybackNetworkRoute.direct,
      transport: CloudPlaybackTransport.rangeRelay,
    );
  }

  Future<XunleiApi> _ensureApi() async {
    final existing = _api;
    if (existing != null && existing.hasUsableSession) return existing;
    final activeRefresh = _refreshing;
    if (activeRefresh != null) {
      await activeRefresh;
      return _requireApi();
    }
    final operation = _authenticateStoredCredential();
    _refreshing = operation;
    try {
      await operation;
      return _requireApi();
    } finally {
      if (identical(_refreshing, operation)) _refreshing = null;
    }
  }

  Future<void> _authenticateStoredCredential() async {
    final credential = await _credentialStore.read(_source.id);
    if (credential == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    await _authenticateCredential(credential);
  }

  Future<void> _authenticateCredential(
    CloudCredential credential, {
    bool replaceExisting = false,
  }) async {
    final refreshToken = credential.refreshToken?.trim();
    final deviceId = credential.deviceId?.trim();
    if (refreshToken == null ||
        refreshToken.isEmpty ||
        deviceId == null ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    final previous = _api;
    final api = _apiFactory(
      deviceId: deviceId,
      captchaToken: credential.captchaToken,
    );
    try {
      final session = await api.refresh(
        refreshToken: refreshToken,
        deviceId: deviceId,
        captchaToken: credential.captchaToken,
      );
      final account = await api.account(session);
      await _credentialStore.write(
        _source.id,
        CloudCredential(
          refreshToken: session.refreshToken,
          deviceId: deviceId,
          captchaToken: api.captchaToken,
          userId: account.userId,
          accountLabel: account.accountLabel,
        ),
      );
      _api = api;
      if (replaceExisting || !identical(previous, api)) {
        await previous?.close();
      }
    } on Object {
      if (!identical(previous, api)) await api.close();
      rethrow;
    }
  }

  XunleiApi _requireApi() {
    final api = _api;
    if (api == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    return api;
  }

  CloudFileEntry _toEntry(XunleiFile file, {required String parentPath}) =>
      CloudFileEntry(
        id: file.id,
        remotePath: p.posix.join(parentPath, file.name),
        name: file.name,
        size: file.size,
        modifiedAt: file.modifiedAt,
        isDirectory: file.isDirectory,
      );

  static XunleiApi _createApi({
    required String deviceId,
    String? captchaToken,
  }) =>
      XunleiApiClient(deviceId: deviceId, captchaToken: captchaToken);

  @override
  Future<void> close() async {
    final refreshing = _refreshing;
    _refreshing = null;
    await refreshing?.catchError((_) {});
    final api = _api;
    _api = null;
    await api?.close();
  }

  @override
  String toString() => 'XunleiDriveClient(sourceId: ${_source.id})';
}
