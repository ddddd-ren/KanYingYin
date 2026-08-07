import 'dart:convert';

const String tvPreloadManifestAsset = 'assets/tv_preload/manifest.json';

final class TvPreloadManifest {
  const TvPreloadManifest({
    required this.enabled,
    required this.version,
    this.configurationAsset,
    this.metadataAsset,
    this.configurationBytes,
    this.metadataBytes,
    this.configurationSha256,
    this.metadataSha256,
  });

  static const int currentVersion = 1;
  static const int maxConfigurationBytes = 512 * 1024;
  static const int maxMetadataBytes = 128 * 1024 * 1024;
  static const String assetPrefix = 'assets/tv_preload/';

  final bool enabled;
  final int version;
  final String? configurationAsset;
  final String? metadataAsset;
  final int? configurationBytes;
  final int? metadataBytes;
  final String? configurationSha256;
  final String? metadataSha256;

  factory TvPreloadManifest.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const TvPreloadManifestException('预置清单格式无效');
    }
    final json = Map<String, Object?>.from(value);
    final version = json['version'];
    if (version != currentVersion) {
      throw const TvPreloadManifestException('预置清单版本不支持');
    }
    if (json['enabled'] != true) {
      return const TvPreloadManifest(enabled: false, version: currentVersion);
    }

    final configurationAsset = _assetPath(
      json['configurationAsset'],
      '.kyyconfig',
    );
    final metadataAsset = _assetPath(json['metadataAsset'], '.kyymeta');
    final configurationBytes = _positiveInt(
      json['configurationBytes'],
      maxConfigurationBytes,
    );
    final metadataBytes = _positiveInt(
      json['metadataBytes'],
      maxMetadataBytes,
    );
    final configurationSha256 = _hash(json['configurationSha256']);
    final metadataSha256 = _hash(json['metadataSha256']);
    return TvPreloadManifest(
      enabled: true,
      version: currentVersion,
      configurationAsset: configurationAsset,
      metadataAsset: metadataAsset,
      configurationBytes: configurationBytes,
      metadataBytes: metadataBytes,
      configurationSha256: configurationSha256,
      metadataSha256: metadataSha256,
    );
  }

  factory TvPreloadManifest.fromBytes(List<int> bytes) {
    try {
      return TvPreloadManifest.fromJson(jsonDecode(utf8.decode(bytes)));
    } on TvPreloadManifestException {
      rethrow;
    } on Object {
      throw const TvPreloadManifestException('预置清单内容无效');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'version': version,
        if (enabled) ...<String, Object?>{
          'configurationAsset': configurationAsset,
          'metadataAsset': metadataAsset,
          'configurationBytes': configurationBytes,
          'metadataBytes': metadataBytes,
          'configurationSha256': configurationSha256,
          'metadataSha256': metadataSha256,
        },
      };

  @override
  String toString() =>
      'TvPreloadManifest(enabled: $enabled, version: $version)';

  static String _assetPath(Object? value, String extension) {
    if (value is! String ||
        !value.startsWith(assetPrefix) ||
        value.contains('..') ||
        value.contains('\\') ||
        !value.toLowerCase().endsWith(extension)) {
      throw const TvPreloadManifestException('预置资源路径无效');
    }
    final fileName = value.substring(assetPrefix.length);
    final expectedName = extension == '.kyyconfig'
        ? 'configuration.kyyconfig'
        : 'metadata.kyymeta';
    if (fileName != expectedName) {
      throw const TvPreloadManifestException('预置资源文件名无效');
    }
    return value;
  }

  static int _positiveInt(Object? value, int maximum) {
    if (value is! int || value <= 0 || value > maximum) {
      throw const TvPreloadManifestException('预置资源大小无效');
    }
    return value;
  }

  static String _hash(Object? value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const TvPreloadManifestException('预置资源哈希无效');
    }
    return value;
  }
}

final class TvPreloadManifestException implements Exception {
  const TvPreloadManifestException(this.message);

  final String message;

  @override
  String toString() => 'TvPreloadManifestException($message)';
}
