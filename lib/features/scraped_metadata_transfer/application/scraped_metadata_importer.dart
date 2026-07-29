import 'dart:io';

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
  const ScrapedMetadataImportException(this.cause);

  final Object cause;

  @override
  String toString() => '刮削资料导入失败，原有资料已恢复：$cause';
}

final class ScrapedMetadataImporter {
  ScrapedMetadataImporter({
    required ILocalMediaIndexRepository localIndexRepository,
    required CloudResourceTmdbRepository resourceRepository,
    required CloudWorkTmdbRepository workRepository,
    required CloudSeriesMatchRuleRepository ruleRepository,
    TransferCacheRootProvider? cacheRootProvider,
    TransferNetworkImageInstaller? networkImageInstaller,
  })  : _localIndexRepository = localIndexRepository,
        _resourceRepository = resourceRepository,
        _workRepository = workRepository,
        _ruleRepository = ruleRepository,
        _cacheRootProvider = cacheRootProvider ?? _defaultCacheRoot,
        _networkImageInstaller =
            networkImageInstaller ?? _defaultNetworkImageInstaller;

  final ILocalMediaIndexRepository _localIndexRepository;
  final CloudResourceTmdbRepository _resourceRepository;
  final CloudWorkTmdbRepository _workRepository;
  final CloudSeriesMatchRuleRepository _ruleRepository;
  final TransferCacheRootProvider _cacheRootProvider;
  final TransferNetworkImageInstaller _networkImageInstaller;

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
    final originalResources = await _resourceRepository.getAll();
    final originalWorks = await _workRepository.getAll();
    final originalRules = await _ruleRepository.getAll();
    var localCommitted = false;
    var resourcesCommitted = false;
    var worksCommitted = false;
    var rulesCommitted = false;

    try {
      await cacheDirectory.create(recursive: true);
      for (final entry in archive.imageFiles.entries) {
        final target = File(p.join(cacheDirectory.path, p.basename(entry.key)));
        if (!await target.exists()) {
          await entry.value.copy(target.path);
          createdImages.add(target);
        }
        installedImages[entry.key] = target.path;
      }
      await _installNetworkImages(plan, installedImages);

      final localUpdates = <String, LocalMediaIndexItem>{};
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
      await _localIndexRepository.updateItems(localUpdates);
      localCommitted = true;

      final nextResources = <String, CloudResourceTmdbRecord>{
        for (final record in originalResources) record.stableKey: record,
      };
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
        nextResources[rebound.stableKey] = rebound;
      }
      await _resourceRepository.replaceAll(nextResources.values);
      resourcesCommitted = true;

      final nextWorks = <String, CloudWorkTmdbRecord>{
        for (final record in originalWorks) record.workKey: record,
      };
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
        nextWorks[rebound.workKey] = rebound;
      }
      await _workRepository.replaceAll(nextWorks.values);
      worksCommitted = true;

      final nextRules = <String, CloudSeriesMatchRule>{
        for (final rule in originalRules) rule.stableKey: rule,
      };
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
        nextRules[rebound.stableKey] = rebound;
      }
      await _ruleRepository.replaceAll(nextRules.values);
      rulesCommitted = true;

      return ScrapedMetadataTransferResult(
        localCount: localUpdates.length,
        cloudCount: plan.cloudResourceMatches.length +
            plan.cloudWorkMatches.length +
            plan.cloudSeriesRuleMatches.length,
        imageCount: installedImages.length,
        skippedCount: plan.missingMediaCount,
      );
    } on Object catch (error, stackTrace) {
      await _rollback(
        originalLocal: originalLocal,
        originalResources: originalResources,
        originalWorks: originalWorks,
        originalRules: originalRules,
        localCommitted: localCommitted,
        resourcesCommitted: resourcesCommitted,
        worksCommitted: worksCommitted,
        rulesCommitted: rulesCommitted,
      );
      for (final image in createdImages.reversed) {
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
        'ScrapedMetadataImporter: import rolled back',
        error: error,
        stackTrace: stackTrace,
      );
      throw ScrapedMetadataImportException(error);
    }
  }

  Future<void> _rollback({
    required Map<String, LocalMediaIndexItem> originalLocal,
    required List<CloudResourceTmdbRecord> originalResources,
    required List<CloudWorkTmdbRecord> originalWorks,
    required List<CloudSeriesMatchRule> originalRules,
    required bool localCommitted,
    required bool resourcesCommitted,
    required bool worksCommitted,
    required bool rulesCommitted,
  }) async {
    final failures = <Object>[];

    Future<void> restore(Future<void> Function() operation) async {
      try {
        await operation();
      } on Object catch (error) {
        failures.add(error);
      }
    }

    if (rulesCommitted) {
      await restore(() => _ruleRepository.replaceAll(originalRules));
    }
    if (worksCommitted) {
      await restore(() => _workRepository.replaceAll(originalWorks));
    }
    if (resourcesCommitted) {
      await restore(() => _resourceRepository.replaceAll(originalResources));
    }
    if (localCommitted) {
      await restore(() => _localIndexRepository.updateItems(originalLocal));
    }
    if (failures.isNotEmpty) {
      AppLogger().e(
        'ScrapedMetadataImporter: rollback incomplete',
        error: failures,
      );
    }
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
