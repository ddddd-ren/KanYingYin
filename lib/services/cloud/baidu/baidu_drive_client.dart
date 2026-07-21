import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_api_client.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_oauth_client.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

typedef BaiduApiFactory = BaiduApi Function(String accessToken);

typedef BaiduTokenRefresher = Future<BaiduOAuthTokens> Function({
  required String clientId,
  required String clientSecret,
  required String refreshToken,
});

class BaiduDriveClient implements CloudDriveClient {
  BaiduDriveClient({
    required CloudSource source,
    required CloudCredentialStore credentialStore,
    BaiduApiFactory? apiFactory,
    BaiduTokenRefresher? tokenRefresher,
    DateTime Function()? now,
  })  : _source = source,
        _credentialStore = credentialStore,
        _apiFactory = apiFactory ??
            ((accessToken) => BaiduApiClient(accessToken: accessToken)),
        _tokenRefresher = tokenRefresher ?? _refreshWithOfficialOAuth,
        _now = now ?? DateTime.now;

  static const Duration _refreshLeadTime = Duration(minutes: 5);

  final CloudSource _source;
  final CloudCredentialStore _credentialStore;
  final BaiduApiFactory _apiFactory;
  final BaiduTokenRefresher _tokenRefresher;
  final DateTime Function() _now;

  BaiduApi? _api;
  String? _apiAccessToken;
  Future<CloudCredential>? _refreshing;
  bool _closed = false;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {
    _validateCredential(credential);
    final api = _apiFactory(credential.accessToken!.trim());
    try {
      await api.account();
    } on Object {
      await api.close();
      rethrow;
    }
    await _api?.close();
    _api = api;
    _apiAccessToken = credential.accessToken!.trim();
    await _credentialStore.write(source.id, credential);
  }

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    final api = await _ensureApi();
    final entries = await api.listDirectory(directory);
    return List<CloudFileEntry>.unmodifiable(
      entries.map(_toCloudFileEntry),
    );
  }

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async {
    final api = await _ensureApi();
    return _toCloudFileEntry(
      await api.fileDetails(file, includeDownloadLink: false),
    );
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async {
    var api = await _ensureApi();
    late final BaiduFileDetails details;
    try {
      details = await api.fileDetails(file, includeDownloadLink: true);
    } on CloudDriveException catch (error) {
      if (error.type != CloudDriveErrorType.authentication) rethrow;
      api = await _forceRefreshApi();
      details = await api.fileDetails(file, includeDownloadLink: true);
    }
    final uri = details.downloadUri;
    if (details.isDirectory || uri == null) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return CloudPlaybackResource(
      uri: uri,
      networkRoute: PlaybackNetworkRoute.direct,
      transport: CloudPlaybackTransport.rangeRelay,
    );
  }

  Future<BaiduApi> _ensureApi() async {
    if (_closed) throw StateError('百度网盘客户端已关闭');
    var credential = await _credentialStore.read(_source.id);
    if (credential == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    _validateCredential(credential);
    if (_shouldRefresh(credential)) {
      credential = await _refreshCredential(credential);
    }
    return _apiForAccessToken(credential.accessToken!.trim());
  }

  Future<BaiduApi> _forceRefreshApi() async {
    final credential = await _credentialStore.read(_source.id);
    if (credential == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    _validateCredential(credential);
    final refreshed = await _refreshCredential(credential);
    return _apiForAccessToken(refreshed.accessToken!.trim());
  }

  Future<BaiduApi> _apiForAccessToken(String accessToken) async {
    final existing = _api;
    if (existing != null && _apiAccessToken == accessToken) return existing;
    await existing?.close();
    _api = _apiFactory(accessToken);
    _apiAccessToken = accessToken;
    return _api!;
  }

  bool _shouldRefresh(CloudCredential credential) {
    final expiresAt = credential.accessTokenExpiresAt;
    if (expiresAt == null) return true;
    return !expiresAt.toUtc().isAfter(_now().toUtc().add(_refreshLeadTime));
  }

  Future<CloudCredential> _refreshCredential(CloudCredential credential) {
    final existing = _refreshing;
    if (existing != null) return existing;
    late final Future<CloudCredential> task;
    task = _performRefresh(credential).whenComplete(() {
      if (identical(_refreshing, task)) _refreshing = null;
    });
    _refreshing = task;
    return task;
  }

  Future<CloudCredential> _performRefresh(CloudCredential credential) async {
    final tokens = await _tokenRefresher(
      clientId: credential.clientId!.trim(),
      clientSecret: credential.clientSecret!.trim(),
      refreshToken: credential.refreshToken!.trim(),
    );
    final refreshed = CloudCredential(
      clientId: credential.clientId!.trim(),
      clientSecret: credential.clientSecret!.trim(),
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessTokenExpiresAt: tokens.expiresAt.toUtc(),
    );
    await _credentialStore.write(_source.id, refreshed);
    return refreshed;
  }

  void _validateCredential(CloudCredential credential) {
    if (credential.clientId?.trim().isEmpty != false ||
        credential.clientSecret?.trim().isEmpty != false ||
        credential.accessToken?.trim().isEmpty != false ||
        credential.refreshToken?.trim().isEmpty != false ||
        credential.accessTokenExpiresAt == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
  }

  CloudFileEntry _toCloudFileEntry(BaiduFileEntry entry) => CloudFileEntry(
        id: entry.fsId,
        remotePath: entry.path,
        name: entry.name,
        size: entry.size,
        modifiedAt: entry.modifiedAt,
        isDirectory: entry.isDirectory,
      );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final api = _api;
    _api = null;
    _apiAccessToken = null;
    await api?.close();
  }

  static Future<BaiduOAuthTokens> _refreshWithOfficialOAuth({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) =>
      BaiduOAuthClient(
        clientId: clientId,
        clientSecret: clientSecret,
      ).refresh(refreshToken);

  @override
  String toString() => 'BaiduDriveClient(sourceId: ${_source.id})';
}
