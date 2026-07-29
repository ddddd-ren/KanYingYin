import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';

const String scrapedMetadataFormat = 'kanyingyin-scraped-metadata';
const int scrapedMetadataFormatVersion = 1;
const int maxTransferRecords = 100000;
const int maxTransferImages = 20000;

final class ScrapedMetadataPayload {
  const ScrapedMetadataPayload({
    required this.formatVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.localSources,
    required this.cloudSources,
  });

  final int formatVersion;
  final DateTime exportedAt;
  final String appVersion;
  final List<PortableLocalSource> localSources;
  final List<PortableCloudSource> cloudSources;

  int get recordCount {
    final local = localSources.fold<int>(
      0,
      (sum, source) => sum + source.records.length,
    );
    final cloud = cloudSources.fold<int>(
      0,
      (sum, source) => sum + source.recordCount,
    );
    return local + cloud;
  }

  factory ScrapedMetadataPayload.fromJson(Map<String, Object?> json) {
    final formatVersion = _requiredInt(json, 'formatVersion');
    if (formatVersion != scrapedMetadataFormatVersion) {
      throw const FormatException('不支持的刮削资料迁移格式版本');
    }
    final exportedAt = DateTime.tryParse(_requiredString(json, 'exportedAt'));
    if (exportedAt == null) {
      throw const FormatException('刮削资料导出时间无效');
    }
    final localSources = _mapList(
      json['localSources'],
      PortableLocalSource.fromJson,
    );
    final cloudSources = _mapList(
      json['cloudSources'],
      PortableCloudSource.fromJson,
    );
    final payload = ScrapedMetadataPayload(
      formatVersion: formatVersion,
      exportedAt: exportedAt.toUtc(),
      appVersion: _requiredString(json, 'appVersion'),
      localSources: localSources,
      cloudSources: cloudSources,
    );
    if (payload.recordCount > maxTransferRecords) {
      throw const FormatException('刮削资料记录数量超过上限');
    }
    return payload;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': formatVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'localSources': localSources.map((source) => source.toJson()).toList(),
        'cloudSources': cloudSources.map((source) => source.toJson()).toList(),
      };
}

final class PortableLocalSource {
  const PortableLocalSource({
    required this.exportId,
    required this.name,
    required this.originalRoot,
    required this.records,
  });

  final String exportId;
  final String name;
  final String originalRoot;
  final List<PortableLocalRecord> records;

  factory PortableLocalSource.fromJson(Map<String, Object?> json) {
    final records = _mapList(json['records'], PortableLocalRecord.fromJson);
    if (records.length > maxTransferRecords) {
      throw const FormatException('本地刮削资料记录数量超过上限');
    }
    return PortableLocalSource(
      exportId: _requiredString(json, 'exportId'),
      name: _requiredString(json, 'name'),
      originalRoot: _requiredString(json, 'originalRoot'),
      records: records,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'exportId': exportId,
        'name': name,
        'originalRoot': originalRoot,
        'records': records.map((record) => record.toJson()).toList(),
      };
}

final class PortableLocalRecord {
  const PortableLocalRecord({
    required this.relativePath,
    required this.size,
    required this.tmdb,
    required this.scrapeStatus,
    required this.tmdbMatchOrigin,
    required this.tmdbRuleVersion,
    this.titleLocked = false,
    this.posterLocked = false,
    this.overviewLocked = false,
    this.manualOverride = false,
    this.posterImage,
    this.backdropImage,
    this.seasonImages = const <int, String>{},
  });

  final String relativePath;
  final int size;
  final Map<String, Object?> tmdb;
  final String scrapeStatus;
  final String tmdbMatchOrigin;
  final int tmdbRuleVersion;
  final bool titleLocked;
  final bool posterLocked;
  final bool overviewLocked;
  final bool manualOverride;
  final String? posterImage;
  final String? backdropImage;
  final Map<int, String> seasonImages;

  factory PortableLocalRecord.fromJson(Map<String, Object?> json) {
    final size = _requiredInt(json, 'size');
    final tmdb = _requiredMap(json, 'tmdb');
    if (size < 0 || _requiredInt(tmdb, 'id') <= 0) {
      throw const FormatException('本地刮削资料媒体信息无效');
    }
    return PortableLocalRecord(
      relativePath: _requiredString(json, 'relativePath'),
      size: size,
      tmdb: tmdb,
      scrapeStatus: _requiredString(json, 'scrapeStatus'),
      tmdbMatchOrigin: _requiredString(json, 'tmdbMatchOrigin'),
      tmdbRuleVersion: _requiredInt(json, 'tmdbRuleVersion'),
      titleLocked: json['titleLocked'] == true,
      posterLocked: json['posterLocked'] == true,
      overviewLocked: json['overviewLocked'] == true,
      manualOverride: json['manualOverride'] == true,
      posterImage: _optionalImagePath(json['posterImage']),
      backdropImage: _optionalImagePath(json['backdropImage']),
      seasonImages: _seasonImages(json['seasonImages']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'relativePath': relativePath,
        'size': size,
        'tmdb': tmdb,
        'scrapeStatus': scrapeStatus,
        'tmdbMatchOrigin': tmdbMatchOrigin,
        'tmdbRuleVersion': tmdbRuleVersion,
        if (titleLocked) 'titleLocked': true,
        if (posterLocked) 'posterLocked': true,
        if (overviewLocked) 'overviewLocked': true,
        if (manualOverride) 'manualOverride': true,
        if (posterImage != null) 'posterImage': posterImage,
        if (backdropImage != null) 'backdropImage': backdropImage,
        if (seasonImages.isNotEmpty)
          'seasonImages': <String, String>{
            for (final entry in seasonImages.entries)
              entry.key.toString(): entry.value,
          },
      };
}

final class PortableCloudRoot {
  const PortableCloudRoot({required this.id, required this.path});

  final String id;
  final String path;

  factory PortableCloudRoot.fromJson(Map<String, Object?> json) =>
      PortableCloudRoot(
        id: _requiredString(json, 'id'),
        path: _requiredString(json, 'path'),
      );

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'path': path};
}

final class PortableCloudRecord {
  const PortableCloudRecord({
    required this.record,
    this.posterImage,
    this.backdropImage,
    this.seasonImages = const <int, String>{},
  });

  final Map<String, Object?> record;
  final String? posterImage;
  final String? backdropImage;
  final Map<int, String> seasonImages;

  factory PortableCloudRecord.fromJson(Map<String, Object?> json) =>
      PortableCloudRecord(
        record: _requiredMap(json, 'record'),
        posterImage: _optionalImagePath(json['posterImage']),
        backdropImage: _optionalImagePath(json['backdropImage']),
        seasonImages: _seasonImages(json['seasonImages']),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'record': record,
        if (posterImage != null) 'posterImage': posterImage,
        if (backdropImage != null) 'backdropImage': backdropImage,
        if (seasonImages.isNotEmpty)
          'seasonImages': <String, String>{
            for (final entry in seasonImages.entries)
              entry.key.toString(): entry.value,
          },
      };
}

final class PortableCloudSource {
  const PortableCloudSource({
    required this.exportId,
    required this.type,
    required this.name,
    required this.sanitizedBaseUrl,
    required this.roots,
    required this.resourceRecords,
    required this.workRecords,
    required this.seriesRules,
  });

  final String exportId;
  final CloudSourceType type;
  final String name;
  final String sanitizedBaseUrl;
  final List<PortableCloudRoot> roots;
  final List<PortableCloudRecord> resourceRecords;
  final List<PortableCloudRecord> workRecords;
  final List<PortableCloudRecord> seriesRules;

  int get recordCount =>
      resourceRecords.length + workRecords.length + seriesRules.length;

  factory PortableCloudSource.fromJson(Map<String, Object?> json) {
    final typeName = _requiredString(json, 'type');
    final type = CloudSourceType.values.cast<CloudSourceType?>().firstWhere(
          (value) => value?.name == typeName,
          orElse: () => null,
        );
    if (type == null) {
      throw const FormatException('网盘来源类型无效');
    }
    return PortableCloudSource(
      exportId: _requiredString(json, 'exportId'),
      type: type,
      name: _requiredString(json, 'name'),
      sanitizedBaseUrl: json['sanitizedBaseUrl'] as String? ?? '',
      roots: _mapList(json['roots'], PortableCloudRoot.fromJson),
      resourceRecords:
          _mapList(json['resourceRecords'], PortableCloudRecord.fromJson),
      workRecords: _mapList(json['workRecords'], PortableCloudRecord.fromJson),
      seriesRules: _mapList(json['seriesRules'], PortableCloudRecord.fromJson),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'exportId': exportId,
        'type': type.name,
        'name': name,
        'sanitizedBaseUrl': sanitizedBaseUrl,
        'roots': roots.map((root) => root.toJson()).toList(),
        'resourceRecords':
            resourceRecords.map((record) => record.toJson()).toList(),
        'workRecords': workRecords.map((record) => record.toJson()).toList(),
        'seriesRules': seriesRules.map((record) => record.toJson()).toList(),
      };
}

final class LocalImportMatch {
  const LocalImportMatch({required this.portable, required this.target});

  final PortableLocalRecord portable;
  final LocalMediaIndexItem target;
}

final class CloudResourceImportMatch {
  const CloudResourceImportMatch({
    required this.portable,
    required this.targetSourceId,
    required this.targetRemoteId,
    required this.targetRemotePath,
  });

  final PortableCloudRecord portable;
  final String targetSourceId;
  final String targetRemoteId;
  final String targetRemotePath;
}

final class CloudWorkImportMatch {
  const CloudWorkImportMatch({
    required this.portable,
    required this.targetSourceId,
    required this.targetWorkKey,
    required this.targetWorkRootId,
    required this.targetWorkRootPath,
  });

  final PortableCloudRecord portable;
  final String targetSourceId;
  final String targetWorkKey;
  final String targetWorkRootId;
  final String targetWorkRootPath;
}

final class CloudSeriesRuleImportMatch {
  const CloudSeriesRuleImportMatch({
    required this.portable,
    required this.targetSourceId,
    required this.targetParentPath,
  });

  final PortableCloudRecord portable;
  final String targetSourceId;
  final String targetParentPath;
}

final class ScrapedMetadataImportPlan {
  const ScrapedMetadataImportPlan({
    required this.payload,
    required this.localMappings,
    required this.cloudMappings,
    required this.localMatches,
    required this.cloudResourceMatches,
    required this.cloudWorkMatches,
    required this.cloudSeriesRuleMatches,
    required this.unresolvedLocalSources,
    required this.unresolvedCloudSources,
    required this.missingMediaCount,
    required this.recoverableImageCount,
  });

  final ScrapedMetadataPayload payload;
  final Map<String, String> localMappings;
  final Map<String, String> cloudMappings;
  final List<LocalImportMatch> localMatches;
  final List<CloudResourceImportMatch> cloudResourceMatches;
  final List<CloudWorkImportMatch> cloudWorkMatches;
  final List<CloudSeriesRuleImportMatch> cloudSeriesRuleMatches;
  final List<PortableLocalSource> unresolvedLocalSources;
  final List<PortableCloudSource> unresolvedCloudSources;
  final int missingMediaCount;
  final int recoverableImageCount;

  int get matchedCount =>
      localMatches.length +
      cloudResourceMatches.length +
      cloudWorkMatches.length +
      cloudSeriesRuleMatches.length;
}

final class ScrapedMetadataTransferResult {
  const ScrapedMetadataTransferResult({
    required this.localCount,
    required this.cloudCount,
    required this.imageCount,
    required this.skippedCount,
  });

  final int localCount;
  final int cloudCount;
  final int imageCount;
  final int skippedCount;
}

List<T> _mapList<T>(
  Object? value,
  T Function(Map<String, Object?> json) fromJson,
) {
  if (value is! List) throw const FormatException('刮削资料列表结构无效');
  return value.map<T>((item) {
    if (item is! Map) throw const FormatException('刮削资料条目结构无效');
    return fromJson(Map<String, Object?>.from(item));
  }).toList(growable: false);
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('刮削资料缺少 $key');
  return Map<String, Object?>.from(value);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('刮削资料缺少 $key');
  }
  return value.trim();
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('刮削资料缺少 $key');
}

String? _optionalImagePath(Object? value) {
  if (value == null) return null;
  if (value is! String ||
      !value.startsWith('images/') ||
      value.contains('\\') ||
      value.contains('..')) {
    throw const FormatException('刮削资料图片路径无效');
  }
  return value;
}

Map<int, String> _seasonImages(Object? value) {
  if (value == null) return const <int, String>{};
  if (value is! Map) throw const FormatException('季度图片结构无效');
  final result = <int, String>{};
  for (final entry in value.entries) {
    final season = int.tryParse(entry.key.toString());
    final path = _optionalImagePath(entry.value);
    if (season == null || season < 0 || path == null) {
      throw const FormatException('季度图片结构无效');
    }
    result[season] = path;
  }
  return Map<int, String>.unmodifiable(result);
}
