import 'package:kanyingyin/features/cloud/application/cloud_directory_scope_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

typedef CloudDirectoryLoader = Future<List<CloudFileEntry>> Function(
  CloudRemoteRef directory,
);

class CloudDirectoryResolution {
  CloudDirectoryResolution({
    required this.current,
    required List<CloudRemoteRef> ancestry,
  }) : ancestry = List<CloudRemoteRef>.unmodifiable(ancestry);

  final CloudRemoteRef current;
  final List<CloudRemoteRef> ancestry;
}

/// 从远程根目录逐级加载并解析地址，确保最终保留真实目录 ID。
class CloudDirectoryAddressResolver {
  const CloudDirectoryAddressResolver({required CloudDirectoryLoader loader})
      : _loader = loader;

  final CloudDirectoryLoader _loader;

  Future<CloudDirectoryResolution> resolve({
    required CloudRemoteRef root,
    required String targetPath,
  }) async {
    final normalizedRoot = CloudDirectoryScopeTree.normalize(root.path);
    final normalizedTarget = CloudDirectoryScopeTree.normalize(targetPath);
    if (normalizedTarget == normalizedRoot) {
      return CloudDirectoryResolution(
        current: root,
        ancestry: const <CloudRemoteRef>[],
      );
    }
    if (normalizedRoot != '/' &&
        !normalizedTarget.startsWith('$normalizedRoot/')) {
      throw const FormatException('目录不存在或无法访问');
    }

    final relative = normalizedRoot == '/'
        ? normalizedTarget.substring(1)
        : normalizedTarget.substring(normalizedRoot.length + 1);
    var current = root;
    var accumulated = normalizedRoot;
    final ancestry = <CloudRemoteRef>[];
    for (final segment in relative.split('/').where(
          (part) => part.isNotEmpty,
        )) {
      final expected =
          accumulated == '/' ? '/$segment' : '$accumulated/$segment';
      final entries = await _loader(current);
      CloudFileEntry? match;
      for (final entry in entries) {
        if (entry.isDirectory &&
            CloudDirectoryScopeTree.normalize(entry.remotePath) == expected) {
          match = entry;
          break;
        }
      }
      if (match == null) {
        throw const FormatException('目录不存在或无法访问');
      }
      ancestry.add(current);
      current = CloudRemoteRef(id: match.id, path: match.remotePath);
      accumulated = expected;
    }
    return CloudDirectoryResolution(
      current: current,
      ancestry: ancestry,
    );
  }
}
