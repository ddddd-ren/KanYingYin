import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

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

@immutable
class TvPairingCloudSourceRecord {
  const TvPairingCloudSourceRecord({
    required this.source,
    this.credential,
  });

  final CloudSource source;
  final CloudCredential? credential;

  factory TvPairingCloudSourceRecord.fromJson(Map<String, dynamic> json) {
    final sourceJson = json['source'];
    if (sourceJson is! Map<Object?, Object?>) {
      throw const TvPairingInvalidPayloadException('网盘来源格式无效');
    }
    final source = CloudSource.fromJson(Map<String, dynamic>.from(sourceJson));
    if (source.id.trim().isEmpty) {
      throw const TvPairingInvalidPayloadException('网盘来源 ID 为空');
    }
    final credentialJson = json['credential'];
    return TvPairingCloudSourceRecord(
      source: source,
      credential: credentialJson is Map<Object?, Object?>
          ? CloudCredential.fromJson(
              Map<String, dynamic>.from(credentialJson),
            )
          : null,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'source': source.toJson(),
        if (credential != null) 'credential': credential!.toJson(),
      };

  @override
  String toString() =>
      'TvPairingCloudSourceRecord(sourceId: ${source.id}, hasCredential: ${credential != null})';
}

@immutable
class TvPairingPayload {
  const TvPairingPayload({
    required this.protocolVersion,
    required this.deviceName,
    required this.tmdbApiKey,
    required this.cloudSources,
  });

  static const int currentProtocolVersion = 1;
  static const int maxPayloadBytes = 256 * 1024;

  final int protocolVersion;
  final String deviceName;
  final String tmdbApiKey;
  final List<TvPairingCloudSourceRecord> cloudSources;

  factory TvPairingPayload.fromJson(Map<String, dynamic> json) {
    final version = json['protocolVersion'];
    if (version is! int || version != currentProtocolVersion) {
      throw const TvPairingInvalidPayloadException('配对协议版本不受支持');
    }
    final deviceName = json['deviceName'];
    final tmdbApiKey = json['tmdbApiKey'];
    final sources = json['cloudSources'];
    if (deviceName is! String ||
        tmdbApiKey is! String ||
        sources is! List<Object?>) {
      throw const TvPairingInvalidPayloadException('配对配置格式无效');
    }
    return TvPairingPayload(
      protocolVersion: version,
      deviceName: deviceName.trim(),
      tmdbApiKey: tmdbApiKey.trim(),
      cloudSources: sources.map((value) {
        if (value is! Map<Object?, Object?>) {
          throw const TvPairingInvalidPayloadException('网盘配置格式无效');
        }
        return TvPairingCloudSourceRecord.fromJson(
          Map<String, dynamic>.from(value),
        );
      }).toList(growable: false),
    );
  }

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

  Map<String, Object> toJson() => <String, Object>{
        'protocolVersion': protocolVersion,
        'deviceName': deviceName,
        'tmdbApiKey': tmdbApiKey,
        'cloudSources': cloudSources
            .map((record) => record.toJson())
            .toList(growable: false),
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
      'TvPairingPayload(protocolVersion: $protocolVersion, deviceName: $deviceName, cloudSourceCount: ${cloudSources.length}, hasTmdbKey: ${tmdbApiKey.isNotEmpty})';
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
