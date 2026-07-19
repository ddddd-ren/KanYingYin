import 'dart:collection';

import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:path/path.dart' as p;

typedef CloudResourceAutoScanProgress = void Function(
  int scannedDirectories,
  int discoveredCandidates,
);

class CloudResourceAutoOrganizeDiscovery {
  CloudResourceAutoOrganizeDiscovery({
    required List<CloudResourceTmdbTarget> candidates,
    required this.scannedDirectories,
    required this.failedDirectories,
  }) : candidates = List<CloudResourceTmdbTarget>.unmodifiable(candidates);

  final List<CloudResourceTmdbTarget> candidates;
  final int scannedDirectories;
  final int failedDirectories;
}

class CloudResourceAutoOrganizer {
  const CloudResourceAutoOrganizer({
    this.maximumDirectories = 1000,
    this.maximumDepth = 20,
  });

  final int maximumDirectories;
  final int maximumDepth;

  static final RegExp _seasonDirectoryPattern = RegExp(
    r'^(?:第\s*[一二三四五六七八九十百〇零两\d]{1,4}\s*季|season\s*\d{1,2}|s\d{1,2})$',
    caseSensitive: false,
  );

  Future<CloudResourceAutoOrganizeDiscovery> discover({
    required CloudSource source,
    required CloudDriveClient client,
    CloudResourceAutoScanProgress? onProgress,
  }) async {
    final queue = Queue<_DirectoryNode>();
    for (final root in source.remoteRoots) {
      queue.add(
        _DirectoryNode(
          remote: root,
          displayName: p.posix.basename(root.path),
          depth: 0,
          isConfiguredRoot: true,
        ),
      );
    }
    final visited = <String>{};
    final candidateKeys = <String>{};
    final candidates = <CloudResourceTmdbTarget>[];
    var scannedDirectories = 0;
    var failedDirectories = 0;
    var successfulRoots = 0;

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      final directoryKey = '${node.remote.id}|${node.remote.path}';
      if (!visited.add(directoryKey)) continue;
      if (node.depth > maximumDepth) {
        throw StateError('自动整理目录深度超过 $maximumDepth 层');
      }
      if (scannedDirectories >= maximumDirectories) {
        throw StateError('自动整理目录数量超过 $maximumDirectories 个');
      }
      scannedDirectories++;
      List<CloudFileEntry> entries;
      try {
        entries = await client.listDirectory(node.remote);
        if (node.isConfiguredRoot) successfulRoots++;
      } on Object {
        failedDirectories++;
        onProgress?.call(scannedDirectories, candidates.length);
        continue;
      }

      final videos = entries
          .where(
            (entry) =>
                !entry.isDirectory &&
                LocalVideoFileTypes.isVideoPath(entry.name),
          )
          .toList(growable: false);
      final directories =
          entries.where((entry) => entry.isDirectory).toList(growable: false);

      if (node.isConfiguredRoot) {
        for (final video in videos) {
          _addCandidate(
            candidates,
            candidateKeys,
            CloudResourceTmdbTarget(
              sourceId: source.id,
              remote: CloudRemoteRef(id: video.id, path: video.remotePath),
              displayName: video.name,
              resourceKind: CloudResourceKind.standaloneVideo,
            ),
          );
        }
        _enqueueDirectories(queue, directories, node.depth + 1);
      } else {
        final hasSeasonDirectory = directories.any(
          (entry) => _seasonDirectoryPattern.hasMatch(entry.name.trim()),
        );
        if (videos.isNotEmpty || hasSeasonDirectory) {
          _addCandidate(
            candidates,
            candidateKeys,
            CloudResourceTmdbTarget(
              sourceId: source.id,
              remote: node.remote,
              displayName: node.displayName,
              resourceKind: CloudResourceKind.directory,
            ),
          );
        } else {
          _enqueueDirectories(queue, directories, node.depth + 1);
        }
      }
      onProgress?.call(scannedDirectories, candidates.length);
    }

    if (source.remoteRoots.isNotEmpty && successfulRoots == 0) {
      throw const CloudDriveException(CloudDriveErrorType.network);
    }
    return CloudResourceAutoOrganizeDiscovery(
      candidates: candidates,
      scannedDirectories: scannedDirectories,
      failedDirectories: failedDirectories,
    );
  }

  static void _enqueueDirectories(
    Queue<_DirectoryNode> queue,
    List<CloudFileEntry> directories,
    int depth,
  ) {
    for (final entry in directories) {
      queue.add(
        _DirectoryNode(
          remote: CloudRemoteRef(id: entry.id, path: entry.remotePath),
          displayName: entry.name,
          depth: depth,
          isConfiguredRoot: false,
        ),
      );
    }
  }

  static void _addCandidate(
    List<CloudResourceTmdbTarget> candidates,
    Set<String> keys,
    CloudResourceTmdbTarget target,
  ) {
    if (keys.add(target.stableKey)) candidates.add(target);
  }
}

class _DirectoryNode {
  const _DirectoryNode({
    required this.remote,
    required this.displayName,
    required this.depth,
    required this.isConfiguredRoot,
  });

  final CloudRemoteRef remote;
  final String displayName;
  final int depth;
  final bool isConfiguredRoot;
}
