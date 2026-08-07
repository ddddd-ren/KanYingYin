import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';

class TvPairingSession {
  TvPairingSession._({
    required this.token,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory TvPairingSession.issue({
    required DateTime now,
    Random? random,
  }) {
    final generator = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => generator.nextInt(256));
    return TvPairingSession._(
      token: base64Url.encode(bytes).replaceAll('=', ''),
      issuedAt: now.toUtc(),
      expiresAt: now.toUtc().add(const Duration(minutes: 5)),
    );
  }

  final String token;
  final DateTime issuedAt;
  final DateTime expiresAt;
  bool _consumed = false;
  bool _cancelled = false;

  bool get isConsumed => _consumed;
  bool get isCancelled => _cancelled;

  bool isExpired(DateTime now) => !now.toUtc().isBefore(expiresAt);

  bool isActive(DateTime now) => !_consumed && !_cancelled && !isExpired(now);

  bool matches(String candidate, {required DateTime now}) {
    return isActive(now) && _constantTimeEquals(token, candidate);
  }

  bool consume(String candidate, {required DateTime now}) {
    if (!matches(candidate, now: now)) return false;
    _consumed = true;
    return true;
  }

  void cancel() {
    _cancelled = true;
  }

  static bool _constantTimeEquals(String expected, String actual) {
    final expectedBytes = utf8.encode(expected);
    final actualBytes = utf8.encode(actual);
    var difference = expectedBytes.length ^ actualBytes.length;
    final length = max(expectedBytes.length, actualBytes.length);
    for (var index = 0; index < length; index++) {
      final expectedByte =
          index < expectedBytes.length ? expectedBytes[index] : 0;
      final actualByte = index < actualBytes.length ? actualBytes[index] : 0;
      difference |= expectedByte ^ actualByte;
    }
    return difference == 0;
  }

  @override
  String toString() =>
      'TvPairingSession(expiresAt: $expiresAt, active: ${isActive(DateTime.now().toUtc())})';
}

@immutable
class TvPairingQrPayload {
  const TvPairingQrPayload({
    required this.host,
    required this.port,
    required this.pairingToken,
    required this.protocolVersion,
  });

  final String host;
  final int port;
  final String pairingToken;
  final int protocolVersion;

  Map<String, Object> toJson() => <String, Object>{
        'host': host,
        'port': port,
        'pairingToken': pairingToken,
        'protocolVersion': protocolVersion,
      };

  String toQrData() => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/pair',
        queryParameters: <String, String>{
          'token': pairingToken,
          'v': protocolVersion.toString(),
        },
      ).toString();

  @override
  String toString() =>
      'TvPairingQrPayload(host: $host, port: $port, protocolVersion: $protocolVersion)';
}

enum TvPairingFileKind {
  configuration('configuration', '.kyyconfig'),
  scrapedMetadata('scrapedMetadata', '.kyymeta');

  const TvPairingFileKind(this.wireValue, this.extension);

  final String wireValue;
  final String extension;

  static TvPairingFileKind fromWireValue(String value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    throw const TvPairingInvalidPayloadException('配对文件类型无效');
  }
}

@immutable
class TvPairingUploadedFile {
  const TvPairingUploadedFile({
    required this.id,
    required this.kind,
    required this.name,
    required this.size,
    required this.path,
  });

  final String id;
  final TvPairingFileKind kind;
  final String name;
  final int size;
  final String path;
}

@immutable
class TvPairingPayload {
  const TvPairingPayload({
    required this.protocolVersion,
    required this.deviceName,
    required this.configuration,
    this.fileIds = const <TvPairingFileKind, String>{},
    this.configurationFilePassword,
    this.uploadedFiles = const <TvPairingFileKind, TvPairingUploadedFile>{},
  });

  static const int currentProtocolVersion = 2;
  static const int maxPayloadBytes = 256 * 1024;
  static const int maxUploadedFileBytes = 64 * 1024 * 1024;

  final int protocolVersion;
  final String deviceName;
  final PortableAppConfiguration configuration;
  final Map<TvPairingFileKind, String> fileIds;
  final String? configurationFilePassword;
  final Map<TvPairingFileKind, TvPairingUploadedFile> uploadedFiles;

  factory TvPairingPayload.fromJson(Map<String, dynamic> json) {
    final version = json['protocolVersion'];
    if (version is! int || version != currentProtocolVersion) {
      throw const TvPairingInvalidPayloadException('配对协议版本不受支持');
    }
    final deviceName = json['deviceName'];
    final configurationJson = json['configuration'];
    if (deviceName is! String ||
        deviceName.trim().isEmpty ||
        deviceName.length > 80 ||
        configurationJson is! Map<Object?, Object?>) {
      throw const TvPairingInvalidPayloadException('配对配置格式无效');
    }
    final fileIds = _parseFileIds(json['fileIds']);
    final configurationFilePassword = json['configurationFilePassword'];
    if (configurationFilePassword != null &&
        configurationFilePassword is! String) {
      throw const TvPairingInvalidPayloadException('配置文件密码格式无效');
    }
    if (fileIds.containsKey(TvPairingFileKind.configuration) &&
        (configurationFilePassword as String?)?.isEmpty != false) {
      throw const TvPairingInvalidPayloadException('配置文件密码不能为空');
    }
    try {
      return TvPairingPayload(
        protocolVersion: version,
        deviceName: deviceName.trim(),
        configuration: PortableAppConfiguration.fromJson(
          Map<String, Object?>.from(configurationJson),
        ),
        fileIds: fileIds,
        configurationFilePassword: configurationFilePassword as String?,
      );
    } on PortableConfigurationValidationException catch (error) {
      throw TvPairingInvalidPayloadException(error.code);
    } on Object {
      throw const TvPairingInvalidPayloadException('配对配置格式无效');
    }
  }

  TvPairingPayload withUploadedFiles(
    Map<TvPairingFileKind, TvPairingUploadedFile> files,
  ) =>
      TvPairingPayload(
        protocolVersion: protocolVersion,
        deviceName: deviceName,
        configuration: configuration,
        fileIds: fileIds,
        configurationFilePassword: configurationFilePassword,
        uploadedFiles:
            Map<TvPairingFileKind, TvPairingUploadedFile>.unmodifiable(
          files,
        ),
      );

  factory TvPairingPayload.decode(List<int> bytes) {
    if (bytes.length > maxPayloadBytes) {
      throw TvPairingPayloadTooLargeException(bytes.length);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) {
        throw const TvPairingInvalidPayloadException('配对配置不是 JSON 对象');
      }
      return TvPairingPayload.fromJson(Map<String, dynamic>.from(decoded));
    } on TvPairingInvalidPayloadException {
      rethrow;
    } on Object {
      throw const TvPairingInvalidPayloadException('配对配置 JSON 无效');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'protocolVersion': protocolVersion,
        'deviceName': deviceName,
        'configuration': configuration.toJson(),
        if (fileIds.isNotEmpty)
          'fileIds': <String, String>{
            for (final entry in fileIds.entries)
              entry.key.wireValue: entry.value,
          },
        if (configurationFilePassword != null)
          'configurationFilePassword': configurationFilePassword,
      };

  Uint8List encode() {
    final bytes = utf8.encode(jsonEncode(toJson()));
    if (bytes.length > maxPayloadBytes) {
      throw TvPairingPayloadTooLargeException(bytes.length);
    }
    return Uint8List.fromList(bytes);
  }

  @override
  String toString() =>
      'TvPairingPayload(protocolVersion: $protocolVersion, deviceName: $deviceName, cloudSourceCount: ${configuration.cloudSources.length}, hasTmdbKey: ${configuration.tmdbApiKey.isNotEmpty})';
}

Map<TvPairingFileKind, String> _parseFileIds(Object? value) {
  if (value == null) return const <TvPairingFileKind, String>{};
  if (value is! Map<Object?, Object?>) {
    throw const TvPairingInvalidPayloadException('配对文件引用格式无效');
  }
  final result = <TvPairingFileKind, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const TvPairingInvalidPayloadException('配对文件引用格式无效');
    }
    final id = (entry.value as String).trim();
    if (id.isEmpty ||
        id.length > 160 ||
        id.contains(RegExp(r'[\u0000-\u001f]'))) {
      throw const TvPairingInvalidPayloadException('配对文件引用无效');
    }
    result[TvPairingFileKind.fromWireValue(entry.key as String)] = id;
  }
  if (result.length > TvPairingFileKind.values.length) {
    throw const TvPairingInvalidPayloadException('配对文件数量超出限制');
  }
  return Map<TvPairingFileKind, String>.unmodifiable(result);
}

class TvPairingPayloadTooLargeException implements Exception {
  const TvPairingPayloadTooLargeException(this.actualBytes);

  final int actualBytes;

  @override
  String toString() =>
      'TvPairingPayloadTooLargeException(actualBytes: $actualBytes)';
}

class TvPairingInvalidPayloadException implements Exception {
  const TvPairingInvalidPayloadException(this.message);

  final String message;

  @override
  String toString() => 'TvPairingInvalidPayloadException($message)';
}
