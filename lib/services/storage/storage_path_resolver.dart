import 'dart:convert';
import 'dart:io';

import 'package:kanyingyin/utils/app_identity.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageStartupConfig {
  const StorageStartupConfig({
    required this.dataRoot,
    required this.cacheRoot,
    this.migrationState = 'ready',
    this.lastSuccessfulDataRoot,
    this.lastSuccessfulCacheRoot,
  });

  final String dataRoot;
  final String cacheRoot;
  final String migrationState;
  final String? lastSuccessfulDataRoot;
  final String? lastSuccessfulCacheRoot;

  factory StorageStartupConfig.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('启动配置不是对象');
    final map = Map<String, Object?>.from(value);
    final dataRoot = map['dataRoot']?.toString().trim() ?? '';
    final cacheRoot = map['cacheRoot']?.toString().trim() ?? '';
    if (dataRoot.isEmpty || cacheRoot.isEmpty) {
      throw const FormatException('启动配置缺少目录');
    }
    return StorageStartupConfig(
      dataRoot: dataRoot,
      cacheRoot: cacheRoot,
      migrationState: map['migrationState']?.toString() ?? 'ready',
      lastSuccessfulDataRoot: map['lastSuccessfulDataRoot']?.toString(),
      lastSuccessfulCacheRoot: map['lastSuccessfulCacheRoot']?.toString(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'dataRoot': dataRoot,
        'cacheRoot': cacheRoot,
        'migrationState': migrationState,
        if (lastSuccessfulDataRoot != null)
          'lastSuccessfulDataRoot': lastSuccessfulDataRoot,
        if (lastSuccessfulCacheRoot != null)
          'lastSuccessfulCacheRoot': lastSuccessfulCacheRoot,
      };
}

class StoragePathResolver {
  static const String readyMigrationState = 'ready';
  static const String pendingMigrationState = 'pending';

  StoragePathResolver({
    required this.dataRoot,
    required this.cacheRoot,
    required this.configFile,
    required this.legacyDataRoot,
    required this.legacyCacheRoot,
    this.isConfigured = false,
    this.migrationState = readyMigrationState,
  });

  final Directory dataRoot;
  final Directory cacheRoot;
  final File configFile;
  final Directory legacyDataRoot;
  final Directory legacyCacheRoot;
  final bool isConfigured;
  final String migrationState;

  static StoragePathResolver? _current;

  static StoragePathResolver? get current => _current;

  static void install(StoragePathResolver resolver) {
    _current = resolver;
  }

  Directory get hiveRoot => Directory(p.join(dataRoot.path, 'hive'));
  Directory get logsRoot => Directory(p.join(dataRoot.path, 'logs'));
  Directory get webViewRoot => Directory(p.join(dataRoot.path, 'webview'));
  Directory get pluginsRoot => Directory(p.join(dataRoot.path, 'plugins'));
  Directory get imageCacheRoot => Directory(p.join(cacheRoot.path, 'images'));
  bool get hasPendingMigration => migrationState == pendingMigrationState;

  StoragePathResolver copyWith({
    Directory? dataRoot,
    Directory? cacheRoot,
    bool? isConfigured,
    String? migrationState,
  }) {
    return StoragePathResolver(
      dataRoot: dataRoot ?? this.dataRoot,
      cacheRoot: cacheRoot ?? this.cacheRoot,
      configFile: configFile,
      legacyDataRoot: legacyDataRoot,
      legacyCacheRoot: legacyCacheRoot,
      isConfigured: isConfigured ?? this.isConfigured,
      migrationState: migrationState ?? this.migrationState,
    );
  }

  Future<void> save() async {
    await _writeConfig(StorageStartupConfig(
      dataRoot: dataRoot.path,
      cacheRoot: cacheRoot.path,
      migrationState: readyMigrationState,
      lastSuccessfulDataRoot: dataRoot.path,
      lastSuccessfulCacheRoot: cacheRoot.path,
    ));
  }

  Future<void> saveMigrationRequest({
    required StoragePathResolver previous,
  }) async {
    await _writeConfig(StorageStartupConfig(
      dataRoot: dataRoot.path,
      cacheRoot: cacheRoot.path,
      migrationState: pendingMigrationState,
      lastSuccessfulDataRoot: previous.dataRoot.path,
      lastSuccessfulCacheRoot: previous.cacheRoot.path,
    ));
  }

  Future<void> _writeConfig(StorageStartupConfig config) async {
    await configFile.parent.create(recursive: true);
    final temporary = File('${configFile.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    if (await configFile.exists()) await configFile.delete();
    await temporary.rename(configFile.path);
  }

  factory StoragePathResolver.fromStartupConfig({
    required StorageStartupConfig config,
    required File configFile,
    required Directory fallbackDataRoot,
    required Directory fallbackCacheRoot,
  }) {
    final pending = config.migrationState == pendingMigrationState;
    final lastData = config.lastSuccessfulDataRoot?.trim();
    final lastCache = config.lastSuccessfulCacheRoot?.trim();
    return StoragePathResolver(
      dataRoot: Directory(config.dataRoot),
      cacheRoot: Directory(config.cacheRoot),
      configFile: configFile,
      legacyDataRoot: pending && lastData != null && lastData.isNotEmpty
          ? Directory(lastData)
          : fallbackDataRoot,
      legacyCacheRoot: pending && lastCache != null && lastCache.isNotEmpty
          ? Directory(lastCache)
          : fallbackCacheRoot,
      isConfigured: true,
      migrationState: config.migrationState,
    );
  }

  static Future<StoragePathResolver> load() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final legacyData = Directory(
      p.join(support.path, AppIdentity.storageNamespace),
    );
    final legacyCache = Directory(cache.path);
    final configFile = File(p.join(support.path, 'storage-startup.json'));
    StorageStartupConfig? config;
    if (await configFile.exists()) {
      try {
        config = StorageStartupConfig.fromJson(
          jsonDecode(await configFile.readAsString()),
        );
      } on Object {
        config = null;
      }
    }
    final defaultRoot = legacyData.parent;
    if (config != null) {
      return StoragePathResolver.fromStartupConfig(
        config: config,
        configFile: configFile,
        fallbackDataRoot: legacyData,
        fallbackCacheRoot: legacyCache,
      );
    }
    final dataRoot = Directory(p.join(defaultRoot.path, '数据'));
    final cacheRoot = Directory(legacyCache.path);
    return StoragePathResolver(
      dataRoot: dataRoot,
      cacheRoot: cacheRoot,
      configFile: configFile,
      legacyDataRoot: legacyData,
      legacyCacheRoot: legacyCache,
    );
  }
}

Future<Directory> defaultImageCacheRoot() async {
  final resolver = StoragePathResolver.current;
  if (resolver != null) return resolver.imageCacheRoot;
  final temporary = await getTemporaryDirectory();
  return Directory(p.join(temporary.path, 'libCachedImageData'));
}
