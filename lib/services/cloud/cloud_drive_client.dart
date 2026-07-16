import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

enum CloudDriveErrorType {
  authentication,
  permission,
  network,
  notFound,
  incompatible,
  expiredLink,
  certificate,
  invalidAddress,
}

class CloudDriveException implements Exception {
  const CloudDriveException(this.type, {this.message});

  final CloudDriveErrorType type;
  final String? message;

  @override
  String toString() => 'CloudDriveException(${type.name})';
}

class CloudPlaybackResource {
  const CloudPlaybackResource({
    required this.uri,
    this.headers = const <String, String>{},
    this.expiresAt,
  });

  final Uri uri;
  final Map<String, String> headers;
  final DateTime? expiresAt;
}

abstract interface class CloudDriveClient {
  Future<void> authenticate(CloudSource source, CloudCredential credential);

  Future<List<CloudFileEntry>> listDirectory(String remotePath);

  Future<CloudFileEntry> getFile(String remotePath);

  Future<CloudPlaybackResource> resolvePlayback(String remotePath);

  Future<void> close();
}
