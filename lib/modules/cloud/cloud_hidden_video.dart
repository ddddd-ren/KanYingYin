import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';

class CloudHiddenVideo {
  const CloudHiddenVideo({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.fileName,
  });

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final String fileName;

  factory CloudHiddenVideo.fromEntry({
    required String sourceId,
    required CloudFileEntry entry,
  }) =>
      CloudHiddenVideo(
        sourceId: sourceId,
        remoteId: entry.id,
        remotePath: normalizeCloudHiddenVideoPath(entry.remotePath),
        fileName: entry.name,
      );

  String get identityKey {
    final normalizedId = remoteId.trim();
    return normalizedId.isNotEmpty
        ? 'id:$normalizedId'
        : 'path:${normalizeCloudHiddenVideoPath(remotePath)}';
  }

  bool matches({
    required String sourceId,
    required String remoteId,
    required String remotePath,
  }) {
    if (this.sourceId != sourceId) return false;
    final hiddenId = this.remoteId.trim();
    final candidateId = remoteId.trim();
    if (hiddenId.isNotEmpty && candidateId.isNotEmpty) {
      return hiddenId == candidateId;
    }
    return normalizeCloudHiddenVideoPath(this.remotePath) ==
        normalizeCloudHiddenVideoPath(remotePath);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceId': sourceId,
        'remoteId': remoteId,
        'remotePath': normalizeCloudHiddenVideoPath(remotePath),
        'fileName': fileName,
      };

  factory CloudHiddenVideo.fromJson(Map<String, Object?> json) {
    String requiredString(String key, {bool allowEmpty = false}) {
      final value = json[key];
      if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
        throw const FormatException('隐藏视频记录字段无效');
      }
      return value;
    }

    return CloudHiddenVideo(
      sourceId: requiredString('sourceId'),
      remoteId: requiredString('remoteId', allowEmpty: true),
      remotePath: normalizeCloudHiddenVideoPath(
        requiredString('remotePath'),
      ),
      fileName: requiredString('fileName'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudHiddenVideo &&
          sourceId == other.sourceId &&
          remoteId == other.remoteId &&
          normalizeCloudHiddenVideoPath(remotePath) ==
              normalizeCloudHiddenVideoPath(other.remotePath) &&
          fileName == other.fileName;

  @override
  int get hashCode => Object.hash(
        sourceId,
        remoteId,
        normalizeCloudHiddenVideoPath(remotePath),
        fileName,
      );
}

String normalizeCloudHiddenVideoPath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  normalized = normalized.replaceAll(RegExp(r'/+'), '/');
  if (normalized.isEmpty) return '/';
  if (!normalized.startsWith('/')) normalized = '/$normalized';
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
