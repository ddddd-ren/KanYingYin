import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:path/path.dart' as p;

final class ScrapedMetadataImportPlanner {
  ScrapedMetadataImportPlanner({
    required ILocalMediaSourceRepository localSourceRepository,
    required ILocalMediaIndexRepository localIndexRepository,
    required CloudSourceRepository cloudSourceRepository,
    required CloudMediaIndexRepository cloudIndexRepository,
  })  : _localSourceRepository = localSourceRepository,
        _localIndexRepository = localIndexRepository,
        _cloudSourceRepository = cloudSourceRepository,
        _cloudIndexRepository = cloudIndexRepository;

  final ILocalMediaSourceRepository _localSourceRepository;
  final ILocalMediaIndexRepository _localIndexRepository;
  final CloudSourceRepository _cloudSourceRepository;
  final CloudMediaIndexRepository _cloudIndexRepository;

  Future<ScrapedMetadataImportPlan> plan(
    ScrapedMetadataPayload payload, {
    Map<String, String> localOverrides = const <String, String>{},
  }) async {
    final localMappings = <String, String>{};
    final localMatches = <LocalImportMatch>[];
    final unresolvedLocal = <PortableLocalSource>[];
    var missingMediaCount = 0;

    final currentLocalSources = _localSourceRepository.getAll();
    for (final portableSource in payload.localSources) {
      final target = _targetLocalSource(
        portableSource,
        currentLocalSources,
        localOverrides[portableSource.exportId],
      );
      if (target == null) {
        unresolvedLocal.add(portableSource);
        missingMediaCount += portableSource.records.length;
        continue;
      }
      localMappings[portableSource.exportId] = target.id;
      final items = _localIndexRepository.getBySourceLocation(target.location);
      final byIdentity = <String, List<LocalMediaIndexItem>>{};
      for (final item in items) {
        final relative = _relativeLocalPath(item.path, target.path);
        if (relative == null) continue;
        byIdentity
            .putIfAbsent(
              '${_normalizedLocalPath(relative)}|${item.size}',
              () => <LocalMediaIndexItem>[],
            )
            .add(item);
      }
      for (final portable in portableSource.records) {
        final candidates = byIdentity[
                '${_normalizedLocalPath(portable.relativePath)}|${portable.size}'] ??
            const <LocalMediaIndexItem>[];
        if (candidates.length == 1) {
          localMatches.add(
            LocalImportMatch(portable: portable, target: candidates.single),
          );
        } else {
          missingMediaCount++;
        }
      }
    }

    final cloudMappings = <String, String>{};
    final cloudResourceMatches = <CloudResourceImportMatch>[];
    final cloudWorkMatches = <CloudWorkImportMatch>[];
    final cloudRuleMatches = <CloudSeriesRuleImportMatch>[];
    final unresolvedCloud = <PortableCloudSource>[];
    final currentCloudSources = await _cloudSourceRepository.getAll();
    for (final portableSource in payload.cloudSources) {
      final candidates = currentCloudSources
          .where(
            (source) =>
                source.type == portableSource.type &&
                _cloudSourceMatches(portableSource, source),
          )
          .toList(growable: false);
      if (candidates.length != 1) {
        unresolvedCloud.add(portableSource);
        missingMediaCount += portableSource.recordCount;
        continue;
      }
      final targetSource = candidates.single;
      cloudMappings[portableSource.exportId] = targetSource.id;
      final items = await _cloudIndexRepository.getBySource(targetSource.id);
      missingMediaCount += _matchCloudRecords(
        portableSource,
        targetSource.id,
        items,
        resourceMatches: cloudResourceMatches,
        workMatches: cloudWorkMatches,
        ruleMatches: cloudRuleMatches,
      );
    }

    return ScrapedMetadataImportPlan(
      payload: payload,
      localMappings: Map<String, String>.unmodifiable(localMappings),
      cloudMappings: Map<String, String>.unmodifiable(cloudMappings),
      localMatches: List<LocalImportMatch>.unmodifiable(localMatches),
      cloudResourceMatches:
          List<CloudResourceImportMatch>.unmodifiable(cloudResourceMatches),
      cloudWorkMatches:
          List<CloudWorkImportMatch>.unmodifiable(cloudWorkMatches),
      cloudSeriesRuleMatches:
          List<CloudSeriesRuleImportMatch>.unmodifiable(cloudRuleMatches),
      unresolvedLocalSources:
          List<PortableLocalSource>.unmodifiable(unresolvedLocal),
      unresolvedCloudSources:
          List<PortableCloudSource>.unmodifiable(unresolvedCloud),
      missingMediaCount: missingMediaCount,
      recoverableImageCount: _imageReferences(payload).length,
    );
  }

  LocalMediaSource? _targetLocalSource(
    PortableLocalSource portable,
    List<LocalMediaSource> current,
    String? overridePath,
  ) {
    if (overridePath != null) {
      return current
          .where(
            (source) =>
                _normalizedLocalPath(source.path) ==
                _normalizedLocalPath(overridePath),
          )
          .firstOrNull;
    }
    final exact = current
        .where(
          (source) =>
              _normalizedLocalPath(source.path) ==
              _normalizedLocalPath(portable.originalRoot),
        )
        .toList(growable: false);
    if (exact.length == 1) return exact.single;

    final scored = <({LocalMediaSource source, double score})>[];
    for (final source in current.where((value) => value.location.isFile)) {
      final items = _localIndexRepository.getBySourceLocation(source.location);
      final identities = <String>{
        for (final item in items)
          if (_relativeLocalPath(item.path, source.path) case final relative?)
            '${_normalizedLocalPath(relative)}|${item.size}',
      };
      final matched = portable.records.where((record) {
        return identities.contains(
          '${_normalizedLocalPath(record.relativePath)}|${record.size}',
        );
      }).length;
      final score =
          portable.records.isEmpty ? 0.0 : matched / portable.records.length;
      if (score >= 0.8 && matched > 0) {
        scored.add((source: source, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) return null;
    if (scored.length > 1 && scored[0].score <= scored[1].score) return null;
    return scored.first.source;
  }

  static bool _cloudSourceMatches(
    PortableCloudSource portable,
    CloudSource current,
  ) {
    if (portable.type == CloudSourceType.openList &&
        portable.sanitizedBaseUrl.isNotEmpty &&
        _sanitizedBaseUrl(current) != portable.sanitizedBaseUrl) {
      return false;
    }
    final portableIds = portable.roots
        .map((root) => root.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final currentIds = current.remoteRoots
        .map((root) => root.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (portableIds.intersection(currentIds).isNotEmpty) return true;

    final portablePaths =
        portable.roots.map((root) => _normalizedRemotePath(root.path)).toSet();
    final currentPaths = current.remoteRoots
        .map((root) => _normalizedRemotePath(root.path))
        .toSet();
    return portablePaths.intersection(currentPaths).isNotEmpty;
  }

  static int _matchCloudRecords(
    PortableCloudSource source,
    String targetSourceId,
    List<CloudMediaIndexItem> items, {
    required List<CloudResourceImportMatch> resourceMatches,
    required List<CloudWorkImportMatch> workMatches,
    required List<CloudSeriesRuleImportMatch> ruleMatches,
  }) {
    var missing = 0;
    for (final portable in source.resourceRecords) {
      final remoteId = portable.record['remoteId'] as String? ?? '';
      final remotePath = portable.record['remotePath'] as String? ?? '';
      final byId = items
          .where((item) => remoteId.isNotEmpty && item.remoteId == remoteId)
          .toList(growable: false);
      final byPath = items
          .where(
            (item) =>
                _normalizedRemotePath(item.remotePath) ==
                _normalizedRemotePath(remotePath),
          )
          .toList(growable: false);
      final candidates = byId.length == 1 ? byId : byPath;
      if (candidates.length != 1 &&
          portable.record['resourceKind'] == 'directory') {
        final directoryTargets = <String, ({String id, String path})>{};
        for (final item in items) {
          final workRootId = item.workRootId?.trim() ?? '';
          final workRootPath = item.workRootPath?.trim() ?? '';
          if (workRootId.isEmpty ||
              _normalizedRemotePath(workRootPath) !=
                  _normalizedRemotePath(remotePath)) {
            continue;
          }
          directoryTargets[
                  '$workRootId|${_normalizedRemotePath(workRootPath)}'] =
              (id: workRootId, path: workRootPath);
        }
        if (directoryTargets.length == 1) {
          final target = directoryTargets.values.single;
          resourceMatches.add(
            CloudResourceImportMatch(
              portable: portable,
              targetSourceId: targetSourceId,
              targetRemoteId: target.id,
              targetRemotePath: target.path,
            ),
          );
          continue;
        }
      }
      if (candidates.length != 1) {
        missing++;
        continue;
      }
      final target = candidates.single;
      resourceMatches.add(
        CloudResourceImportMatch(
          portable: portable,
          targetSourceId: targetSourceId,
          targetRemoteId: target.remoteId,
          targetRemotePath: target.remotePath,
        ),
      );
    }

    for (final portable in source.workRecords) {
      final rootId = portable.record['workRootId'] as String? ?? '';
      final rootPath = portable.record['workRootPath'] as String? ?? '';
      final candidates = items.where((item) {
        if (rootId.isNotEmpty && item.workRootId == rootId) return true;
        return _normalizedRemotePath(item.workRootPath ?? '') ==
            _normalizedRemotePath(rootPath);
      }).toList(growable: false);
      final target = candidates
          .where((item) => item.workKey?.isNotEmpty == true)
          .firstOrNull;
      if (target == null) {
        missing++;
        continue;
      }
      workMatches.add(
        CloudWorkImportMatch(
          portable: portable,
          targetSourceId: targetSourceId,
          targetWorkKey: target.workKey!,
          targetWorkRootId: target.workRootId ?? rootId,
          targetWorkRootPath: target.workRootPath ?? rootPath,
        ),
      );
    }

    for (final portable in source.seriesRules) {
      final parentPath = portable.record['parentPath'] as String? ?? '';
      final hasMedia = items.any(
        (item) => _isWithinRemotePath(item.remotePath, parentPath),
      );
      if (!hasMedia) {
        missing++;
        continue;
      }
      ruleMatches.add(
        CloudSeriesRuleImportMatch(
          portable: portable,
          targetSourceId: targetSourceId,
          targetParentPath: _normalizedRemotePath(parentPath),
        ),
      );
    }
    return missing;
  }

  static Set<String> _imageReferences(ScrapedMetadataPayload payload) {
    final result = <String>{};
    void addRecordImages(
      String? poster,
      String? backdrop,
      Map<int, String> seasons,
    ) {
      if (poster != null) result.add(poster);
      if (backdrop != null) result.add(backdrop);
      result.addAll(seasons.values);
    }

    for (final source in payload.localSources) {
      for (final record in source.records) {
        addRecordImages(
          record.posterImage,
          record.backdropImage,
          record.seasonImages,
        );
      }
    }
    for (final source in payload.cloudSources) {
      for (final record in <PortableCloudRecord>[
        ...source.resourceRecords,
        ...source.workRecords,
        ...source.seriesRules,
      ]) {
        addRecordImages(
          record.posterImage,
          record.backdropImage,
          record.seasonImages,
        );
      }
    }
    return result;
  }

  static String? _relativeLocalPath(String itemPath, String rootPath) {
    final relative = p.relative(itemPath, from: rootPath);
    if (relative == '.' ||
        relative == '..' ||
        relative.startsWith('..${p.separator}')) {
      return null;
    }
    return relative.replaceAll('\\', '/');
  }

  static String _normalizedLocalPath(String value) => value
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp('/+'), '/')
      .toLowerCase();

  static String _normalizedRemotePath(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp('/+'), '/');
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool _isWithinRemotePath(String child, String parent) {
    final normalizedChild = _normalizedRemotePath(child);
    final normalizedParent = _normalizedRemotePath(parent);
    return normalizedChild == normalizedParent ||
        normalizedChild.startsWith('$normalizedParent/');
  }

  static String _sanitizedBaseUrl(CloudSource source) {
    final uri = Uri.tryParse(source.baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}
