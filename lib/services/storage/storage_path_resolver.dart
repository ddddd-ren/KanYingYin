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
    await validateDirectorySeparation();
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
    await previous.validateDirectorySeparation();
    await validateDirectorySeparation();
    await _writeConfig(StorageStartupConfig(
      dataRoot: dataRoot.path,
      cacheRoot: cacheRoot.path,
      migrationState: pendingMigrationState,
      lastSuccessfulDataRoot: previous.dataRoot.path,
      lastSuccessfulCacheRoot: previous.cacheRoot.path,
    ));
  }

  Future<void> validateDirectorySeparation() async {
    void check(String data, String cache) {
      data = p.canonicalize(data);
      cache = p.canonicalize(cache);
      if (p.equals(data, cache) ||
          p.isWithin(data, cache) ||
          p.isWithin(cache, data)) {
        throw const FileSystemException('应用数据目录和缓存目录不能相同或互相包含，请选择独立目录');
      }
    }

    check(
      p.normalize(dataRoot.absolute.path),
      p.normalize(cacheRoot.absolute.path),
    );
    final resolvedCache = await _resolvedDirectoryPath(cacheRoot);
    check(await _resolvedDirectoryPath(dataRoot), resolvedCache);
    final resolvedConfig = await _resolvedDirectoryPath(Directory(configFile.path));
    if (p.equals(cacheRoot.path, configFile.path) ||
        p.isWithin(cacheRoot.path, configFile.path) ||
        p.equals(resolvedCache, resolvedConfig) ||
        p.isWithin(resolvedCache, resolvedConfig)) {
      throw const FileSystemException('缓存目录不能包含启动配置文件，请选择独立目录');
    }
  }

  static Future<String> _resolvedDirectoryPath(Directory directory) async {
    var existing = Directory(p.normalize(directory.absolute.path));
    final suffix = <String>[];
    // 尚未创建的目录也要解析已有祖先，避免通过符号链接或目录联接绕过校验。
    while (await FileSystemEntity.type(existing.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = existing.parent;
      if (p.equals(parent.path, existing.path)) {
        throw FileSystemException('无法确认存储目录的实际位置', directory.path);
      }
      suffix.add(p.basename(existing.path));
      existing = parent;
    }
    return p.normalize(p.joinAll([
      await existing.resolveSymbolicLinks(),
      ...suffix.reversed,
    ]));
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
      final resolver = StoragePathResolver.fromStartupConfig(
        config: config,
        configFile: configFile,
        fallbackDataRoot: legacyData,
        fallbackCacheRoot: legacyCache,
      );
      await resolver.validateDirectorySeparation();
      return resolver;
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
