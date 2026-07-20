import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';
import 'package:path/path.dart' as p;

typedef QuarkApiFactory = QuarkApi Function(String cookie);

class QuarkDriveClient implements CloudDriveClient {
  QuarkDriveClient({
    required CloudSource source,
    required CloudCredentialStore credentialStore,
    QuarkApiFactory? apiFactory,
  })  : _source = source,
        _credentialStore = credentialStore,
        _apiFactory =
            apiFactory ?? ((cookie) => QuarkApiClient(cookie: cookie));

  static const int _pageSize = 50;
  static const int _maxPages = 200;

  final CloudSource _source;
  final CloudCredentialStore _credentialStore;
  final QuarkApiFactory _apiFactory;
  QuarkApi? _api;
  String? _cookie;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {
    final cookie = credential.cookie?.trim();
    if (cookie == null || cookie.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    await _api?.close();
    final api = _apiFactory(cookie);
    try {
      await api.getAccount();
    } on Object {
      await api.close();
      rethrow;
    }
    _api = api;
    _cookie = cookie;
    await _credentialStore.write(
      source.id,
      CloudCredential(cookie: cookie),
    );
  }

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    final api = await _ensureApi();
    final entries = <CloudFileEntry>[];
    final seenIds = <String>{};
    Set<String>? previousPageIds;
    for (var page = 1; page <= _maxPages; page++) {
      final result = await api.listDirectoryPage(
        directoryId: directory.id,
        page: page,
        size: _pageSize,
      );
      if (result.page != page || result.size <= 0 || result.total < 0) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      final pageIds = result.items.map((item) => item.id).toSet();
      if (pageIds.isNotEmpty &&
          previousPageIds != null &&
          _sameSet(pageIds, previousPageIds)) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      previousPageIds = pageIds;
      for (final item in result.items) {
        if (!seenIds.add(item.id)) continue;
        entries.add(CloudFileEntry(
          id: item.id,
          remotePath: p.posix.join(directory.path, item.name),
          name: item.name,
          size: item.size,
          modifiedAt: item.modifiedAt,
          isDirectory: item.isDirectory,
        ));
      }
      if (result.items.isEmpty ||
          entries.length >= result.total ||
          page * result.size >= result.total) {
        return List<CloudFileEntry>.unmodifiable(entries);
      }
    }
    throw const CloudDriveException(CloudDriveErrorType.incompatible);
  }

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async => CloudFileEntry(
        id: file.id,
        remotePath: file.path,
        name: p.posix.basename(file.path),
        size: 0,
        modifiedAt: null,
        isDirectory: false,
      );

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async {
    final api = await _ensureApi();
    final playback = await api.resolvePlayback(file.id);
    final cookie = _cookie;
    if (cookie == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    return CloudPlaybackResource(
      uri: playback.uri,
      networkRoute: PlaybackNetworkRoute.direct,
      // 转码 CDN 不接受夸克 API 使用的 JSON 请求头与 Cookie。
      headers: const <String, String>{},
    );
  }

  Future<QuarkApi> _ensureApi() async {
    final existing = _api;
    if (existing != null) return existing;
    final credential = await _credentialStore.read(_source.id);
    final cookie = credential?.cookie?.trim();
    if (cookie == null || cookie.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    _cookie = cookie;
    return _api = _apiFactory(cookie);
  }

  @override
  Future<void> close() async {
    final api = _api;
    _api = null;
    _cookie = null;
    await api?.close();
  }

  static bool _sameSet(Set<String> first, Set<String> second) =>
      first.length == second.length && first.containsAll(second);

  @override
  String toString() => 'QuarkDriveClient(sourceId: ${_source.id})';
}
