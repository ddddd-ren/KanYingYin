import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:path/path.dart' as p;

abstract interface class CachedImageLookup {
  Future<File?> find(String url);
}

final class FlutterCachedImageLookup implements CachedImageLookup {
  @override
  Future<File?> find(String url) async =>
      (await DefaultCacheManager().getFileFromCache(url))?.file;
}

final class ScrapedMetadataExportDraft {
  const ScrapedMetadataExportDraft({
    required this.payload,
    required this.images,
    required this.skippedCount,
  });

  final ScrapedMetadataPayload payload;
  final Map<String, File> images;
  final int skippedCount;
}

final class ScrapedMetadataExporter {
  ScrapedMetadataExporter({
    required ILocalMediaIndexRepository localIndexRepository,
    required ILocalMediaSourceRepository localSourceRepository,
    required CloudSourceRepository cloudSourceRepository,
    required CloudResourceTmdbRepository resourceRepository,
    required CloudWorkTmdbRepository workRepository,
    required CloudSeriesMatchRuleRepository ruleRepository,
    CachedImageLookup? cachedImageLookup,
    required String appVersion,
    DateTime Function()? clock,
  })  : _localIndexRepository = localIndexRepository,
        _localSourceRepository = localSourceRepository,
        _cloudSourceRepository = cloudSourceRepository,
        _resourceRepository = resourceRepository,
        _workRepository = workRepository,
        _ruleRepository = ruleRepository,
        _cachedImageLookup = cachedImageLookup ?? FlutterCachedImageLookup(),
        _appVersion = appVersion,
        _clock = clock ?? DateTime.now;

  final ILocalMediaIndexRepository _localIndexRepository;
  final ILocalMediaSourceRepository _localSourceRepository;
  final CloudSourceRepository _cloudSourceRepository;
  final CloudResourceTmdbRepository _resourceRepository;
  final CloudWorkTmdbRepository _workRepository;
  final CloudSeriesMatchRuleRepository _ruleRepository;
  final CachedImageLookup _cachedImageLookup;
  final String _appVersion;
  final DateTime Function() _clock;

  final Map<String, File> _images = <String, File>{};
  var _skippedCount = 0;

  Future<ScrapedMetadataExportDraft> build() async {
    _images.clear();
    _skippedCount = 0;
    final localSources = await _buildLocalSources();
    final cloudSources = await _buildCloudSources();
    return ScrapedMetadataExportDraft(
      payload: ScrapedMetadataPayload(
        formatVersion: scrapedMetadataFormatVersion,
        exportedAt: _clock().toUtc(),
        appVersion: _appVersion,
        localSources: localSources,
        cloudSources: cloudSources,
      ),
      images: Map<String, File>.unmodifiable(_images),
      skippedCount: _skippedCount,
    );
  }

  Future<List<PortableLocalSource>> _buildLocalSources() async {
    final result = <PortableLocalSource>[];
    for (final source in _localSourceRepository.getAll()) {
      final records = <PortableLocalRecord>[];
      for (final item
          in _localIndexRepository.getBySourceLocation(source.location)) {
        final metadata = item.tmdb;
        if (item.scrapeStatus != TmdbScrapeStatus.matched ||
            metadata == null ||
            metadata.id <= 0) {
          _skippedCount++;
          continue;
        }
        final relativePath = _relativePath(item.path, source.path);
        if (relativePath == null) {
          _skippedCount++;
          continue;
        }
        records.add(
          PortableLocalRecord(
            relativePath: relativePath,
            size: item.size,
            tmdb: _stripCachePaths(metadata.toJson()),
            scrapeStatus: item.scrapeStatus.name,
            tmdbMatchOrigin: item.tmdbMatchOrigin.name,
            tmdbRuleVersion: item.tmdbRuleVersion,
            titleLocked: item.titleLocked,
            posterLocked: item.posterLocked,
            overviewLocked: item.overviewLocked,
            manualOverride: item.manualOverride,
            posterImage: await _imageReference(
              explicitPath: item.cover,
              url: metadata.posterUrl,
            ),
            backdropImage: await _imageReference(url: metadata.backdropUrl),
            seasonImages: await _seasonImages(metadata.seasons),
          ),
        );
      }
      if (records.isNotEmpty) {
        result.add(
          PortableLocalSource(
            exportId: source.id,
            name: source.name,
            originalRoot: source.path,
            records: records,
          ),
        );
      }
    }
    return result;
  }

  Future<List<PortableCloudSource>> _buildCloudSources() async {
    final result = <PortableCloudSource>[];
    for (final source in await _cloudSourceRepository.getAll()) {
      final resources = <PortableCloudRecord>[];
      for (final record in await _resourceRepository.getBySource(source.id)) {
        if (record.status != CloudResourceTmdbStatus.matched ||
            (record.tmdbId ?? 0) <= 0) {
          _skippedCount++;
          continue;
        }
        resources.add(
          await _portableCloudRecord(
            record.toJson(),
            posterPath: record.posterCachePath,
            posterUrl: record.posterUrl,
            backdropUrl: record.backdropUrl,
            seasons: record.seasons,
          ),
        );
      }

      final works = <PortableCloudRecord>[];
      for (final record in await _workRepository.getBySource(source.id)) {
        final metadata = record.metadata;
        if (record.status.name != 'matched' ||
            metadata == null ||
            metadata.id <= 0) {
          _skippedCount++;
          continue;
        }
        works.add(
          await _portableCloudRecord(
            record.toJson(),
            posterPath: record.posterCachePath,
            posterUrl: metadata.posterUrl,
            backdropUrl: metadata.backdropUrl,
            seasons: metadata.seasons,
          ),
        );
      }

      final rules = <PortableCloudRecord>[];
      for (final rule in await _ruleRepository.getBySource(source.id)) {
        if (rule.metadata.id <= 0) {
          _skippedCount++;
          continue;
        }
        rules.add(
          await _portableCloudRecord(
            rule.toJson(),
            posterPath: rule.posterCachePath,
            posterUrl: rule.metadata.posterUrl,
            backdropUrl: rule.metadata.backdropUrl,
            seasons: rule.metadata.seasons,
          ),
        );
      }

      if (resources.isEmpty && works.isEmpty && rules.isEmpty) continue;
      result.add(
        PortableCloudSource(
          exportId: source.id,
          type: source.type,
          name: source.name,
          sanitizedBaseUrl: _sanitizedBaseUrl(source),
          roots: source.remoteRoots
              .map((root) => PortableCloudRoot(id: root.id, path: root.path))
              .toList(growable: false),
          resourceRecords: resources,
          workRecords: works,
          seriesRules: rules,
        ),
      );
    }
    return result;
  }

  Future<PortableCloudRecord> _portableCloudRecord(
    Map<String, Object?> json, {
    required String? posterPath,
    required String? posterUrl,
    required String? backdropUrl,
    required List<TmdbSeasonMetadata> seasons,
  }) async {
    return PortableCloudRecord(
      record: _stripCachePaths(json),
      posterImage: await _imageReference(
        explicitPath: posterPath,
        url: posterUrl,
      ),
      backdropImage: await _imageReference(url: backdropUrl),
      seasonImages: await _seasonImages(seasons),
    );
  }

  Future<Map<int, String>> _seasonImages(
    List<TmdbSeasonMetadata> seasons,
  ) async {
    final result = <int, String>{};
    for (final season in seasons) {
      final image = await _imageReference(
        explicitPath: season.posterCachePath,
        url: season.posterUrl,
      );
      if (image != null) result[season.seasonNumber] = image;
    }
    return result;
  }

  Future<String?> _imageReference({
    String? explicitPath,
    String? url,
  }) async {
    File? file;
    final path = explicitPath?.trim();
    if (path != null && path.isNotEmpty) {
      final candidate = File(path);
      if (await candidate.exists()) file = candidate;
    }
    if (file == null && url?.trim().isNotEmpty == true) {
      file = await _cachedImageLookup.find(url!.trim());
      if (file != null && !await file.exists()) file = null;
    }
    if (file == null) return null;

    final hash = (await sha256.bind(file.openRead()).first).toString();
    final extension = _safeImageExtension(file.path, url);
    final packagePath = 'images/$hash$extension';
    _images.putIfAbsent(packagePath, () => file!);
    return packagePath;
  }

  static Map<String, Object?> _stripCachePaths(Map<String, Object?> source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      if (entry.key == 'posterCachePath' || entry.key == 'backdropCachePath') {
        continue;
      }
      final value = entry.value;
      if (value is Map) {
        result[entry.key] = _stripCachePaths(
          Map<String, Object?>.from(value),
        );
      } else if (value is List) {
        result[entry.key] = value.map((item) {
          if (item is Map) {
            return _stripCachePaths(Map<String, Object?>.from(item));
          }
          return item;
        }).toList(growable: false);
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static String? _relativePath(String itemPath, String rootPath) {
    final relative = p.relative(itemPath, from: rootPath);
    if (relative == '.' ||
        relative == '..' ||
        relative.startsWith('..${p.separator}')) {
      return null;
    }
    return relative.replaceAll('\\', '/');
  }

  static String _safeImageExtension(String filePath, String? url) {
    const allowed = <String>{'.jpg', '.jpeg', '.png', '.webp'};
    final fileExtension = p.extension(filePath).toLowerCase();
    if (allowed.contains(fileExtension)) return fileExtension;
    final urlExtension =
        p.extension(Uri.tryParse(url ?? '')?.path ?? '').toLowerCase();
    return allowed.contains(urlExtension) ? urlExtension : '.jpg';
  }

  static String _sanitizedBaseUrl(CloudSource source) {
    if (source.type != CloudSourceType.openList) return '';
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
