import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';

class CloudSeriesPropagationResult {
  CloudSeriesPropagationResult({
    required this.eligible,
    required this.ruleSaved,
    required List<CloudResourceTmdbRecord> records,
    required this.indexSyncFailures,
    required List<CloudResourceTmdbTarget> pendingIndexSyncTargets,
  })  : records = List<CloudResourceTmdbRecord>.unmodifiable(records),
        pendingIndexSyncTargets = List<CloudResourceTmdbTarget>.unmodifiable(
          pendingIndexSyncTargets,
        );

  const CloudSeriesPropagationResult.notEligible()
      : eligible = false,
        ruleSaved = true,
        records = const <CloudResourceTmdbRecord>[],
        indexSyncFailures = 0,
        pendingIndexSyncTargets = const <CloudResourceTmdbTarget>[];

  final bool eligible;
  final bool ruleSaved;
  final List<CloudResourceTmdbRecord> records;
  final int indexSyncFailures;
  final List<CloudResourceTmdbTarget> pendingIndexSyncTargets;
}

class CloudSeriesRuleApplication {
  const CloudSeriesRuleApplication({
    required this.record,
    required this.metadata,
    required this.indexSynced,
  });

  final CloudResourceTmdbRecord record;
  final TmdbMetadata metadata;
  final bool indexSynced;
}

class CloudSeriesMatchService {
  CloudSeriesMatchService({
    required CloudSeriesMatchRuleRepository ruleRepository,
    required CloudResourceTmdbRepository recordRepository,
    required CloudMediaIndexRepository indexRepository,
    CloudSeriesIdentityResolver? identityResolver,
    int Function()? minRecognizedVideoSizeBytesProvider,
    DateTime Function()? now,
  })  : _ruleRepository = ruleRepository,
        _recordRepository = recordRepository,
        _indexRepository = indexRepository,
        _identityResolver = identityResolver ?? CloudSeriesIdentityResolver(),
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ??
                (() => LocalVideoFileTypes.minRecognizedVideoSizeBytes),
        _now = now ?? DateTime.now;

  final CloudSeriesMatchRuleRepository _ruleRepository;
  final CloudResourceTmdbRepository _recordRepository;
  final CloudMediaIndexRepository _indexRepository;
  final CloudSeriesIdentityResolver _identityResolver;
  final int Function() _minRecognizedVideoSizeBytesProvider;
  final DateTime Function() _now;

  CloudSeriesEpisodeIdentity? identityFor(CloudResourceTmdbTarget target) {
    final size = target.size;
    if (target.resourceKind != CloudResourceKind.standaloneVideo ||
        size == null) {
      return null;
    }
    return _identityResolver.resolve(
      sourceId: target.sourceId,
      remotePath: target.remote.path,
      size: size,
      minSizeBytes: _minRecognizedVideoSizeBytesProvider(),
    );
  }

  Future<CloudSeriesPropagationResult> learnAndPropagate({
    required CloudResourceTmdbTarget anchor,
    required CloudResourceTmdbRecord anchorRecord,
    required List<CloudResourceTmdbTarget> candidates,
    required Map<String, CloudResourceTmdbRecord> existingRecords,
    required String language,
  }) async {
    final anchorIdentity = identityFor(anchor);
    if (anchorIdentity == null ||
        anchorRecord.status != CloudResourceTmdbStatus.matched ||
        anchorRecord.mediaType != TmdbMediaType.tv) {
      return const CloudSeriesPropagationResult.notEligible();
    }
    final metadata = _metadataFromRecord(anchorRecord, language: language);
    if (metadata == null) {
      return const CloudSeriesPropagationResult.notEligible();
    }
    final rule = CloudSeriesMatchRule(
      sourceId: anchorIdentity.sourceId,
      parentPath: anchorIdentity.parentPath,
      normalizedSeriesName: anchorIdentity.normalizedSeriesName,
      metadata: metadata,
      posterCachePath: anchorRecord.posterCachePath,
      updatedAt: _now(),
    );
    var ruleSaved = true;
    try {
      await _ruleRepository.upsert(rule);
    } on Object {
      ruleSaved = false;
    }

    final propagationEntries = <_PropagationEntry>[];
    for (final target in candidates) {
      if (target.stableKey == anchor.stableKey) continue;
      final identity = identityFor(target);
      if (identity?.stableKey != anchorIdentity.stableKey) continue;
      final existing = existingRecords[target.stableKey];
      if (_mustPreserve(existing, target)) continue;
      propagationEntries.add(
        _PropagationEntry(
          target: target,
          record: _matchedRecord(
            target: target,
            metadata: metadata,
            posterCachePath: anchorRecord.posterCachePath,
          ),
        ),
      );
    }
    final records =
        propagationEntries.map((entry) => entry.record).toList(growable: false);
    if (records.isNotEmpty) await _recordRepository.upsertAll(records);

    final pendingTargets = <CloudResourceTmdbTarget>[];
    for (final entry in propagationEntries) {
      if (!await syncRecordToIndex(
        target: entry.target,
        record: entry.record,
      )) {
        pendingTargets.add(entry.target);
      }
    }
    return CloudSeriesPropagationResult(
      eligible: true,
      ruleSaved: ruleSaved,
      records: records,
      indexSyncFailures: pendingTargets.length,
      pendingIndexSyncTargets: pendingTargets,
    );
  }

  Future<CloudSeriesRuleApplication?> applyRule({
    required CloudResourceTmdbTarget target,
    CloudResourceTmdbRecord? existingRecord,
  }) async {
    if (_mustPreserve(existingRecord, target)) return null;
    final identity = identityFor(target);
    if (identity == null) return null;
    final rule = await _ruleRepository.get(identity.stableKey);
    if (rule == null || rule.metadata.mediaType != TmdbMediaType.tv) {
      return null;
    }
    final record = _matchedRecord(
      target: target,
      metadata: rule.metadata,
      posterCachePath: rule.posterCachePath,
    );
    await _recordRepository.upsert(record);
    final indexSynced = await syncRecordToIndex(
      target: target,
      record: record,
    );
    return CloudSeriesRuleApplication(
      record: record,
      metadata: rule.metadata,
      indexSynced: indexSynced,
    );
  }

  Future<bool> syncRecordToIndex({
    required CloudResourceTmdbTarget target,
    required CloudResourceTmdbRecord record,
  }) async {
    final metadata = _metadataFromRecord(record, language: 'zh-CN');
    if (metadata == null) return false;
    try {
      final targetPath = CloudSeriesIdentityResolver.normalizeRemotePath(
        target.remote.path,
      );
      await _indexRepository.updateMatching(
        target.sourceId,
        (item) =>
            CloudSeriesIdentityResolver.normalizeRemotePath(
              item.remotePath,
            ) ==
            targetPath,
        (item) => _replaceMetadata(
          item,
          metadata,
          record.posterCachePath,
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  bool _mustPreserve(
    CloudResourceTmdbRecord? existing,
    CloudResourceTmdbTarget target,
  ) {
    final existingCustom = existing?.customTitle?.trim();
    final targetCustom = target.customTitle?.trim();
    return existing?.status == CloudResourceTmdbStatus.matched ||
        (existingCustom != null && existingCustom.isNotEmpty) ||
        (targetCustom != null && targetCustom.isNotEmpty);
  }

  CloudResourceTmdbRecord _matchedRecord({
    required CloudResourceTmdbTarget target,
    required TmdbMetadata metadata,
    required String? posterCachePath,
  }) {
    return CloudResourceTmdbRecord.matched(
      sourceId: target.sourceId,
      remoteId: target.remote.id,
      remotePath: target.remote.path,
      displayName: target.displayName,
      resourceKind: target.resourceKind,
      metadata: metadata,
      checkedAt: _now(),
      posterCachePath: posterCachePath,
      customTitle: target.customTitle,
    );
  }

  static TmdbMetadata? _metadataFromRecord(
    CloudResourceTmdbRecord record, {
    required String language,
  }) {
    final id = record.tmdbId;
    final mediaType = record.mediaType;
    final title = record.title?.trim();
    if (id == null ||
        id <= 0 ||
        mediaType == null ||
        title == null ||
        title.isEmpty) {
      return null;
    }
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: title,
      originalTitle: record.originalTitle,
      overview: record.overview,
      releaseDate: record.releaseDate,
      rating: record.rating,
      posterUrl: record.posterUrl,
      backdropUrl: record.backdropUrl,
      language: language,
      matchedAt: record.checkedAt,
      matchConfidence: 1,
      seasons: record.seasons,
    );
  }

  static CloudMediaIndexItem _replaceMetadata(
    CloudMediaIndexItem item,
    TmdbMetadata metadata,
    String? posterCachePath,
  ) {
    return item.replaceTmdb(
      tmdbId: metadata.id,
      tmdbTitle: metadata.title,
      tmdbOriginalTitle: metadata.originalTitle,
      tmdbOverview: metadata.overview,
      tmdbRating: metadata.rating,
      tmdbPosterUrl: metadata.posterUrl,
      tmdbBackdropUrl: metadata.backdropUrl,
      posterCachePath: posterCachePath,
    );
  }
}

class _PropagationEntry {
  const _PropagationEntry({required this.target, required this.record});

  final CloudResourceTmdbTarget target;
  final CloudResourceTmdbRecord record;
}
