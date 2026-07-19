import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

enum CloudDriveErrorType {
  authentication,
  permission,
  network,
  notFound,
  incompatible,
  expiredLink,
  certificate,
  invalidAddress,
  timeout,
  rateLimited,
  shareExpired,
  invalidPasscode,
  insufficientSpace,
  taskFailed,
  taskTimeout,
  cancelled,
}

class CloudDriveException implements Exception {
  const CloudDriveException(this.type, {this.message});

  final CloudDriveErrorType type;
  final String? message;

  @override
  String toString() => 'CloudDriveException(${type.name})';
}

enum PlaybackNetworkRoute { inheritProxy, direct }

class CloudPlaybackResource {
  const CloudPlaybackResource({
    required this.uri,
    this.headers = const <String, String>{},
    this.expiresAt,
    this.networkRoute = PlaybackNetworkRoute.inheritProxy,
  });

  final Uri uri;
  final Map<String, String> headers;
  final DateTime? expiresAt;
  final PlaybackNetworkRoute networkRoute;
}

abstract interface class CloudDriveClient {
  Future<void> authenticate(CloudSource source, CloudCredential credential);

  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory);

  Future<CloudFileEntry> getFile(CloudRemoteRef file);

  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file);

  Future<void> close();
}
