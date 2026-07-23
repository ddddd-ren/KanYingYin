import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';

/// 将夸克转存目录持久化为可扫描的媒体目录。
abstract final class QuarkTransferTargetPolicy {
  static CloudSource apply(CloudSource source, CloudRemoteRef target) {
    final normalizedTarget = CloudSourcePathScope.normalizePath(target.path);
    final roots = List<CloudRemoteRef>.from(source.remoteRoots);
    final exactIndex = roots.indexWhere(
      (root) =>
          CloudSourcePathScope.normalizePath(root.path) == normalizedTarget,
    );
    if (exactIndex >= 0) {
      roots[exactIndex] = target;
    } else if (!CloudSourcePathScope.containsSourcePath(source, target.path)) {
      roots.add(target);
    }
    return source.copyWith(
      defaultTransferDirectory: target,
      rootRefs: List<CloudRemoteRef>.unmodifiable(roots),
      rootPaths: List<String>.unmodifiable(
        roots.map((root) => root.path),
      ),
    );
  }
}
