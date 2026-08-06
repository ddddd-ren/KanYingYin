import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

@immutable
final class PortableCloudSourceConfiguration {
  const PortableCloudSourceConfiguration._({
    required this.source,
    required this.credential,
  });

  factory PortableCloudSourceConfiguration.fromSource({
    required CloudSource source,
    CloudCredential? credential,
  }) {
    final sanitized = CloudSource(
      id: source.id.trim(),
      type: source.type,
      name: source.name.trim(),
      baseUrl: source.baseUrl.trim(),
      rootPaths: List<String>.unmodifiable(
        source.rootPaths
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      ),
      rootRefs: List.unmodifiable(source.rootRefs),
      defaultTransferDirectory: source.defaultTransferDirectory,
      enabled: source.enabled,
      allowSelfSignedCertificate: source.allowSelfSignedCertificate,
    );
    _validateSource(sanitized);
    return PortableCloudSourceConfiguration._(
      source: sanitized,
      credential: credential == null || credential.isEmpty ? null : credential,
    );
  }

  factory PortableCloudSourceConfiguration.fromJson(
    Map<String, Object?> json,
  ) {
    final sourceJson = json['source'];
    if (sourceJson is! Map<Object?, Object?>) {
      throw const PortableConfigurationValidationException('invalid_source');
    }
    final credentialJson = json['credential'];
    if (credentialJson != null && credentialJson is! Map<Object?, Object?>) {
      throw const PortableConfigurationValidationException(
        'invalid_credential',
      );
    }
    try {
      return PortableCloudSourceConfiguration.fromSource(
        source: CloudSource.fromJson(Map<String, dynamic>.from(sourceJson)),
        credential: credentialJson is Map<Object?, Object?>
            ? CloudCredential.fromJson(
                Map<String, dynamic>.from(credentialJson),
              )
            : null,
      );
    } on PortableConfigurationValidationException {
      rethrow;
    } on Object {
      throw const PortableConfigurationValidationException('invalid_source');
    }
  }

  final CloudSource source;
  final CloudCredential? credential;

  bool get requiresRootSelection =>
      source.type != CloudSourceType.openList &&
      source.rootPaths.isEmpty &&
      source.rootRefs.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': source.toJson(),
        if (credential != null) 'credential': credential!.toJson(),
      };

  @override
  String toString() =>
      'PortableCloudSourceConfiguration(sourceId: ${source.id}, '
      'type: ${source.type.name}, hasCredential: ${credential != null})';

  static void _validateSource(CloudSource source) {
    if (source.id.isEmpty || source.id.length > 128) {
      throw const PortableConfigurationValidationException(
        'invalid_source_id',
      );
    }
    if (source.name.isEmpty || source.name.length > 120) {
      throw const PortableConfigurationValidationException(
        'invalid_source_name',
      );
    }
    final uri = Uri.tryParse(source.baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      throw const PortableConfigurationValidationException(
        'invalid_source_url',
      );
    }
    final fixedUrl = switch (source.type) {
      CloudSourceType.openList => null,
      CloudSourceType.quark => 'https://pan.quark.cn',
      CloudSourceType.baidu => 'https://pan.baidu.com',
      CloudSourceType.xunlei => 'https://pan.xunlei.com',
    };
    if (fixedUrl != null && source.baseUrl != fixedUrl) {
      throw const PortableConfigurationValidationException(
        'invalid_provider_url',
      );
    }
    if (source.rootPaths.length > 64 ||
        source.rootPaths.any((value) => value.length > 1024) ||
        source.rootRefs.length > 64 ||
        source.rootRefs.any(
          (value) => value.id.length > 2048 || value.path.length > 2048,
        )) {
      throw const PortableConfigurationValidationException(
        'invalid_root_paths',
      );
    }
  }
}

@immutable
final class PortableAppConfiguration {
  const PortableAppConfiguration._({
    required this.formatVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.tmdbApiKey,
    required this.cloudSources,
  });

  static const int currentFormatVersion = 1;
  static const int maxCloudSourceCount = 100;

  factory PortableAppConfiguration.create({
    required DateTime exportedAt,
    required String appVersion,
    required String tmdbApiKey,
    required List<PortableCloudSourceConfiguration> cloudSources,
  }) =>
      PortableAppConfiguration._validated(
        formatVersion: currentFormatVersion,
        exportedAt: exportedAt,
        appVersion: appVersion,
        tmdbApiKey: tmdbApiKey,
        cloudSources: cloudSources,
      );

  factory PortableAppConfiguration.fromJson(Map<String, Object?> json) {
    final sourcesJson = json['cloudSources'];
    if (sourcesJson is! List<Object?>) {
      throw const PortableConfigurationValidationException('invalid_sources');
    }
    final exportedAt = DateTime.tryParse(json['exportedAt']?.toString() ?? '');
    return PortableAppConfiguration._validated(
      formatVersion: json['formatVersion'],
      exportedAt: exportedAt,
      appVersion: json['appVersion'],
      tmdbApiKey: json['tmdbApiKey'],
      cloudSources: sourcesJson.map((value) {
        if (value is! Map<Object?, Object?>) {
          throw const PortableConfigurationValidationException(
            'invalid_source',
          );
        }
        return PortableCloudSourceConfiguration.fromJson(
          Map<String, Object?>.from(value),
        );
      }).toList(growable: false),
    );
  }

  factory PortableAppConfiguration._validated({
    required Object? formatVersion,
    required DateTime? exportedAt,
    required Object? appVersion,
    required Object? tmdbApiKey,
    required List<PortableCloudSourceConfiguration> cloudSources,
  }) {
    if (formatVersion != currentFormatVersion) {
      throw const PortableConfigurationValidationException(
        'unsupported_format_version',
      );
    }
    if (exportedAt == null ||
        appVersion is! String ||
        appVersion.trim().isEmpty ||
        appVersion.length > 80) {
      throw const PortableConfigurationValidationException('invalid_metadata');
    }
    if (tmdbApiKey is! String || tmdbApiKey.length > 16384) {
      throw const PortableConfigurationValidationException('invalid_tmdb_key');
    }
    if (cloudSources.length > maxCloudSourceCount) {
      throw const PortableConfigurationValidationException('too_many_sources');
    }
    final sourceIds = <String>{};
    for (final record in cloudSources) {
      if (!sourceIds.add(record.source.id)) {
        throw const PortableConfigurationValidationException(
          'duplicate_source_id',
        );
      }
    }
    return PortableAppConfiguration._(
      formatVersion: currentFormatVersion,
      exportedAt: exportedAt.toUtc(),
      appVersion: appVersion.trim(),
      tmdbApiKey: tmdbApiKey.trim(),
      cloudSources: List<PortableCloudSourceConfiguration>.unmodifiable(
        cloudSources,
      ),
    );
  }

  final int formatVersion;
  final DateTime exportedAt;
  final String appVersion;
  final String tmdbApiKey;
  final List<PortableCloudSourceConfiguration> cloudSources;

  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': formatVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersion': appVersion,
        'tmdbApiKey': tmdbApiKey,
        'cloudSources':
            cloudSources.map((value) => value.toJson()).toList(growable: false),
      };

  @override
  String toString() =>
      'PortableAppConfiguration(formatVersion: $formatVersion, '
      'appVersion: $appVersion, cloudSourceCount: ${cloudSources.length}, '
      'hasTmdbKey: ${tmdbApiKey.isNotEmpty})';
}

final class PortableConfigurationValidationException implements Exception {
  const PortableConfigurationValidationException(this.code);

  final String code;

  @override
  String toString() => 'PortableConfigurationValidationException($code)';
}
