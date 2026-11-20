import 'dart:io';
import 'dart:convert';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef TransferCacheRootProvider = Future<Directory> Function();
typedef TransferNetworkImageInstaller = Future<void> Function({
  required String url,
  required File file,
});

final class ScrapedMetadataImportException implements Exception {
  const ScrapedMetadataImportException(this.cause,
      {this.originalRestored = true});

  final Object cause;
  final bool originalRestored;

  @override
  String toString() => originalRestored
      ? '刮削资料导入失败，原有资料已恢复：$cause'
      : '刮削资料导入失败，自动恢复未完整完成，已保留导入图片，请检查当前资料后重试';
}

final class ScrapedMetadataImporter {
  ScrapedMetadataImporter({
    required ILocalMediaIndexRepository localIndexRepository,
    required CloudResourceTmdbRepository resourceRepository,
    required CloudWorkTmdbRepository workRepository,
    required CloudSeriesMatchRuleRepository ruleRepository,
    TransferCacheRootProvider? cacheRootProvider,
    TransferNetworkImageInstaller? networkImageInstaller,
    Future<void> Function(ScrapedMetadataImportPlan)? validateCloudTargets,
  })  : _localIndexRepository = localIndexRepository,
        _resourceRepository = resourceRepository,
        _workRepository = workRepository,
        _ruleRepository = ruleRepository,
        _validateCloudTargets = validateCloudTargets,
        _cacheRootProvider = cacheRootProvider ?? _defaultCacheRoot,
        _networkImageInstaller =
            networkImageInstaller ?? _defaultNetworkImageInstaller;

  final ILocalMediaIndexRepository _localIndexRepository;
  final CloudResourceTmdbRepository _resourceRepository;
  final CloudWorkTmdbRepository _workRepository;
  final CloudSeriesMatchRuleRepository _ruleRepository;
  final TransferCacheRootProvider _cacheRootProvider;
  final TransferNetworkImageInstaller _networkImageInstaller;
  final Future<void> Function(ScrapedMetadataImportPlan)? _validateCloudTargets;

  Future<ScrapedMetadataTransferResult> apply(
    ScrapedMetadataImportPlan plan,
    DecodedScrapedMetadataArchive archive,
  ) async {
    final cacheDirectory = Directory(
      p.join((await _cacheRootProvider()).path, 'scraped_metadata'),
    );
    final installedImages = <String, String>{};
    final createdImages = <File>[];
    final originalLocal = <String, LocalMediaIndexItem>{};
    final localUpdates = <String, LocalMediaIndexItem>{};
    final originalResources = {
      for (final record in await _resourceRepository.getAll())
        record.stableKey: record,
    };
    final originalWorks = {
      for (final record in await _workRepository.getAll())
        record.workKey: record,
    };
    final originalRules = {
      for (final rule in await _ruleRepository.getAll()) rule.stableKey: rule,
    };
    final resourceUpdates = <String, CloudResourceTmdbRecord>{};
    final workUpdates = <String, CloudWorkTmdbRecord>{};
    final ruleUpdates = <String, CloudSeriesMatchRule>{};
    var localTouched = false;
    var resourcesTouched = false;
    var worksTouched = false;
    var rulesTouched = false;

    try {
      await cacheDirectory.create(recursive: true);
      for (final entry in archive.imageFiles.entries) {
        final target = File(p.join(cacheDirectory.path, p.basename(entry.key)));
        if (!await target.exists()) {
          createdImages.add(target);
          await entry.value.copy(target.path);
        }
        installedImages[entry.key] = target.path;
      }
      await _installNetworkImages(plan, installedImages);
      await _validateCloudTargets?.call(plan);

      for (final match in plan.localMatches) {
        final current =
            _localIndexRepository.getByLocation(match.target.location);
        if (current == null ||
            current.size != match.portable.size ||
            current.id != match.target.id) {
          continue;
        }
        originalLocal[current.id] = current;
        final metadata = _metadataWithSeasonImages(
          TmdbMetadata.fromJson(
            Map<String, dynamic>.from(match.portable.tmdb),
          ),
          match.portable.seasonImages,
          installedImages,
        );
        localUpdates[current.id] = current.copyWith(
          tmdb: metadata,
          titleLocked: match.portable.titleLocked,
          posterLocked: match.portable.posterLocked,
          overviewLocked: match.portable.overviewLocked,
          scrapeStatus: _scrapeStatus(match.portable.scrapeStatus),
          tmdbMatchOrigin: _matchOrigin(match.portable.tmdbMatchOrigin),
          tmdbRuleVersion: match.portable.tmdbRuleVersion,
          manualOverride: match.portable.manualOverride,
          cover: _installedPath(
                match.portable.posterImage,
                installedImages,
              ) ??
              current.cover,
        );
      }
      localTouched = true;
      await _localIndexRepository.patchItems(localUpdates,
          originals: originalLocal);

      for (final match in plan.cloudResourceMatches) {
        final portable = CloudResourceTmdbRecord.fromJson(
          match.portable.record,
        );
        final rebound = portable.rebindForTransfer(
          sourceId: match.targetSourceId,
          remoteId: match.targetRemoteId,
          remotePath: match.targetRemotePath,
          posterCachePath: _installedPath(
            match.portable.posterImage,
            installedImages,
          ),
          seasons: _seasonsWithImages(
            portable.seasons,
            match.portable.seasonImages,
            installedImages,
          ),
        );
        resourceUpdates[rebound.stableKey] = rebound;
      }
      resourcesTouched = true;
      await _resourceRepository.patchRecords(resourceUpdates, originals: {
        for (final key in resourceUpdates.keys) key: originalResources[key]
      });

      for (final match in plan.cloudWorkMatches) {
        final portable = CloudWorkTmdbRecord.fromJson(match.portable.record);
        final metadata = portable.metadata;
        if (metadata == null) continue;
        final rebound = portable.rebindForTransfer(
          sourceId: match.targetSourceId,
          workKey: match.targetWorkKey,
          workRootId: match.targetWorkRootId,
          workRootPath: match.targetWorkRootPath,
          posterCachePath: _installedPath(
            match.portable.posterImage,
            installedImages,
          ),
          metadata: _metadataWithSeasonImages(
            metadata,
            match.portable.seasonImages,
            installedImages,
          ),
        );
        workUpdates[rebound.workKey] = rebound;
      }
      worksTouched = true;
      await _workRepository.patchRecords(workUpdates, originals: {
        for (final key in workUpdates.keys) key: originalWorks[key]
      });

      for (final match in plan.cloudSeriesRuleMatches) {
        final portable = CloudSeriesMatchRule.fromJson(match.portable.record);
        final rebound = portable.rebindForTransfer(
          sourceId: match.targetSourceId,
          parentPath: match.targetParentPath,
          posterCachePath: _installedPath(
            match.portable.posterImage,
            installedImages,
          ),
          metadata: _metadataWithSeasonImages(
            portable.metadata,
            match.portable.seasonImages,
            installedImages,
          ),
        );
        ruleUpdates[rebound.stableKey] = rebound;
      }
      rulesTouched = true;
      await _ruleRepository.patchRecords(ruleUpdates, originals: {
        for (final key in ruleUpdates.keys) key: originalRules[key]
      });

      return ScrapedMetadataTransferResult(
        localCount: localUpdates.length,
        cloudCount:
            resourceUpdates.length + workUpdates.length + ruleUpdates.length,
        imageCount: installedImages.length,
        skippedCount: plan.missingMediaCount,
      );
    } on Object catch (error, stackTrace) {
      final originalRestored = await _rollback(
        originalLocal: originalLocal,
        localUpdates: localUpdates,
        originalResources: originalResources,
        originalWorks: originalWorks,
        originalRules: originalRules,
        resourceUpdates: resourceUpdates,
        workUpdates: workUpdates,
        ruleUpdates: ruleUpdates,
        localTouched: localTouched,
        resourcesTouched: resourcesTouched,
        worksTouched: worksTouched,
        rulesTouched: rulesTouched,
      );
      // 尝试写入后，新图片可能已被并发编辑引用，失败时保留缓存以免误删。
      final retainImages =
          localTouched || resourcesTouched || worksTouched || rulesTouched;
      for (final image in retainImages ? <File>[] : createdImages.reversed) {
        try {
          if (await image.exists()) await image.delete();
        } on Object catch (cleanupError, cleanupStackTrace) {
          AppLogger().w(
            'ScrapedMetadataImporter: failed to remove imported image',
            error: cleanupError,
            stackTrace: cleanupStackTrace,
          );
        }
      }
      AppLogger().w(
        'ScrapedMetadataImporter: import failed, restored=$originalRestored, '
        '保留可能已被引用的图片缓存=$retainImages',
        error: error,
        stackTrace: stackTrace,
      );
      throw ScrapedMetadataImportException(error,
          originalRestored: originalRestored);
    }
  }

  Future<bool> _rollback({
    required Map<String, LocalMediaIndexItem> originalLocal,
    required Map<String, LocalMediaIndexItem> localUpdates,
    required Map<String, CloudResourceTmdbRecord> originalResources,
    required Map<String, CloudWorkTmdbRecord> originalWorks,
    required Map<String, CloudSeriesMatchRule> originalRules,
    required Map<String, CloudResourceTmdbRecord> resourceUpdates,
    required Map<String, CloudWorkTmdbRecord> workUpdates,
    required Map<String, CloudSeriesMatchRule> ruleUpdates,
    required bool localTouched,
    required bool resourcesTouched,
    required bool worksTouched,
    required bool rulesTouched,
  }) async {
    final failures = <Object>[];

    Future<void> restore(Future<void> Function() operation) async {
      try {
        await operation();
      } on Object catch (error) {
        failures.add(error);
      }
    }

    Future<void> restoreCloud(Future<Set<String>> Function() operation) =>
        restore(() async {
          if ((await operation()).isNotEmpty) {
            throw StateError('导入期间资料已被修改，已保留并发修改');
          }
        });

    if (rulesTouched) {
      await restoreCloud(() => _ruleRepository.patchRecords(
          {for (final key in ruleUpdates.keys) key: originalRules[key]},
          originals: ruleUpdates, skipConflicts: true));
    }
    if (worksTouched) {
      await restoreCloud(() => _workRepository.patchRecords(
          {for (final key in workUpdates.keys) key: originalWorks[key]},
          originals: workUpdates, skipConflicts: true));
    }
    if (resourcesTouched) {
      await restoreCloud(() => _resourceRepository.patchRecords(
          {for (final key in resourceUpdates.keys) key: originalResources[key]},
          originals: resourceUpdates, skipConflicts: true));
    }
    if (localTouched) {
      await restore(() async {
        await _localIndexRepository.patchItems(originalLocal,
            originals: localUpdates);
        for (final original in originalLocal.values) {
          final current =
              _localIndexRepository.getByLocation(original.location);
          final before = original.toJson()..remove('indexedAtMillis');
          final actual = current?.toJson()?..remove('indexedAtMillis');
          if (jsonEncode(before) != jsonEncode(actual)) {
            throw StateError('本地资料已有并发修改或目标已删除，未强制覆盖恢复');
          }
        }
      });
    }
    if (failures.isNotEmpty) {
      AppLogger().e(
        'ScrapedMetadataImporter: rollback incomplete',
        error: failures,
      );
    }
    return failures.isEmpty;
  }

  Future<void> _installNetworkImages(
    ScrapedMetadataImportPlan plan,
    Map<String, String> installedImages,
  ) async {
    final installedUrls = <String>{};

    Future<void> install(String? url, String? packagePath) async {
      final normalizedUrl = url?.trim() ?? '';
      final installedPath = _installedPath(packagePath, installedImages);
      if (normalizedUrl.isEmpty ||
          installedPath == null ||
          !installedUrls.add(normalizedUrl)) {
        return;
      }
      await _networkImageInstaller(
        url: normalizedUrl,
        file: File(installedPath),
      );
    }

    Future<void> installMetadata(
      TmdbMetadata metadata,
      String? posterImage,
      String? backdropImage,
      Map<int, String> seasonImages,
    ) async {
      await install(metadata.posterUrl, posterImage);
      await install(metadata.backdropUrl, backdropImage);
      for (final season in metadata.seasons) {
        await install(
          season.posterUrl,
          seasonImages[season.seasonNumber],
        );
      }
    }

    for (final match in plan.localMatches) {
      await installMetadata(
        TmdbMetadata.fromJson(
          Map<String, dynamic>.from(match.portable.tmdb),
        ),
        match.portable.posterImage,
        match.portable.backdropImage,
        match.portable.seasonImages,
      );
    }
    for (final match in plan.cloudResourceMatches) {
      final record = CloudResourceTmdbRecord.fromJson(match.portable.record);
      await install(record.posterUrl, match.portable.posterImage);
      await install(record.backdropUrl, match.portable.backdropImage);
      for (final season in record.seasons) {
        await install(
          season.posterUrl,
          match.portable.seasonImages[season.seasonNumber],
        );
      }
    }
    for (final match in plan.cloudWorkMatches) {
      final metadata =
          CloudWorkTmdbRecord.fromJson(match.portable.record).metadata;
      if (metadata != null) {
        await installMetadata(
          metadata,
          match.portable.posterImage,
          match.portable.backdropImage,
          match.portable.seasonImages,
        );
      }
    }
    for (final match in plan.cloudSeriesRuleMatches) {
      final metadata =
          CloudSeriesMatchRule.fromJson(match.portable.record).metadata;
      await installMetadata(
        metadata,
        match.portable.posterImage,
        match.portable.backdropImage,
        match.portable.seasonImages,
      );
    }
  }

  static TmdbMetadata _metadataWithSeasonImages(
    TmdbMetadata metadata,
    Map<int, String> seasonImages,
    Map<String, String> installedImages,
  ) {
    return metadata.copyWith(
      seasons: _seasonsWithImages(
        metadata.seasons,
        seasonImages,
        installedImages,
      ),
    );
  }

  static List<TmdbSeasonMetadata> _seasonsWithImages(
    List<TmdbSeasonMetadata> seasons,
    Map<int, String> seasonImages,
    Map<String, String> installedImages,
  ) {
    return seasons.map((season) {
      final packagePath = seasonImages[season.seasonNumber];
      final installedPath = _installedPath(packagePath, installedImages);
      return installedPath == null
          ? season
          : season.copyWith(posterCachePath: installedPath);
    }).toList(growable: false);
  }

  static String? _installedPath(
    String? packagePath,
    Map<String, String> installedImages,
  ) =>
      packagePath == null ? null : installedImages[packagePath];

  static TmdbScrapeStatus _scrapeStatus(String value) =>
      TmdbScrapeStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => TmdbScrapeStatus.matched,
      );

  static TmdbMatchOrigin _matchOrigin(String value) =>
      TmdbMatchOrigin.values.firstWhere(
        (origin) => origin.name == value,
        orElse: () => TmdbMatchOrigin.legacyUnknown,
      );

  static Future<Directory> _defaultCacheRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, AppIdentity.storageNamespace));
  }

  static Future<void> _defaultNetworkImageInstaller({
    required String url,
    required File file,
  }) async {
    final extension = p.extension(file.path).replaceFirst('.', '');
    await DefaultCacheManager().putFile(
      url,
      await file.readAsBytes(),
      key: url,
      maxAge: const Duration(days: 3650),
      fileExtension: extension.isEmpty ? 'image' : extension,
    );
  }
}
