import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

enum CloudSourceType { openList, quark }

enum CloudScanStatus { never, scanning, completed, failed }

class CloudSource {
  const CloudSource({
    required this.id,
    required this.type,
    required this.name,
    required this.baseUrl,
    required this.rootPaths,
    this.rootRefs = const <CloudRemoteRef>[],
    this.enabled = true,
    this.allowSelfSignedCertificate = false,
    this.lastScannedAt,
    this.scanStatus = CloudScanStatus.never,
    this.indexedVideoCount = 0,
    this.matchedSubtitleCount = 0,
    this.lastScanFailureCount = 0,
  });

  final String id;
  final CloudSourceType type;
  final String name;
  final String baseUrl;
  final List<String> rootPaths;
  final List<CloudRemoteRef> rootRefs;
  final bool enabled;
  final bool allowSelfSignedCertificate;
  final DateTime? lastScannedAt;
  final CloudScanStatus scanStatus;
  final int indexedVideoCount;
  final int matchedSubtitleCount;
  final int lastScanFailureCount;

  /// 旧 OpenList 配置没有文件 ID，继续使用路径作为稳定引用。
  List<CloudRemoteRef> get remoteRoots => rootRefs.isNotEmpty
      ? rootRefs
      : rootPaths
          .map((path) => CloudRemoteRef(id: path, path: path))
          .toList(growable: false);

  factory CloudSource.fromJson(Map<String, dynamic> json) => CloudSource(
        id: _stringValue(json['id']),
        type: CloudSourceType.values.firstWhere(
          (value) => value.name == json['type'],
          orElse: () => CloudSourceType.openList,
        ),
        name: _stringValue(json['name']),
        baseUrl: _stringValue(json['baseUrl']),
        rootPaths: (json['rootPaths'] is List
                ? json['rootPaths'] as List
                : const <Object>[])
            .whereType<String>()
            .toList(growable: false),
        rootRefs: (json['rootRefs'] is List
                ? json['rootRefs'] as List
                : const <Object>[])
            .whereType<Map>()
            .map((value) => CloudRemoteRef.fromJson(
                  Map<String, dynamic>.from(value),
                ))
            .toList(growable: false),
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
        allowSelfSignedCertificate: json['allowSelfSignedCertificate'] is bool
            ? json['allowSelfSignedCertificate'] as bool
            : false,
        lastScannedAt: _dateValue(json['lastScannedAt']),
        scanStatus: CloudScanStatus.values.firstWhere(
          (value) => value.name == json['scanStatus'],
          orElse: () => CloudScanStatus.never,
        ),
        indexedVideoCount: _intValue(json['indexedVideoCount']),
        matchedSubtitleCount: _intValue(json['matchedSubtitleCount']),
        lastScanFailureCount: _intValue(json['lastScanFailureCount']),
      );

  static String _stringValue(Object? value) => value is String ? value : '';

  static DateTime? _dateValue(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int _intValue(Object? value) => value is num ? value.toInt() : 0;

  CloudSource copyWith({
    String? name,
    String? baseUrl,
    List<String>? rootPaths,
    List<CloudRemoteRef>? rootRefs,
    bool? enabled,
    bool? allowSelfSignedCertificate,
    DateTime? lastScannedAt,
    CloudScanStatus? scanStatus,
    int? indexedVideoCount,
    int? matchedSubtitleCount,
    int? lastScanFailureCount,
  }) =>
      CloudSource(
        id: id,
        type: type,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        rootPaths: rootPaths ?? this.rootPaths,
        rootRefs: rootRefs ?? this.rootRefs,
        enabled: enabled ?? this.enabled,
        allowSelfSignedCertificate:
            allowSelfSignedCertificate ?? this.allowSelfSignedCertificate,
        lastScannedAt: lastScannedAt ?? this.lastScannedAt,
        scanStatus: scanStatus ?? this.scanStatus,
        indexedVideoCount: indexedVideoCount ?? this.indexedVideoCount,
        matchedSubtitleCount: matchedSubtitleCount ?? this.matchedSubtitleCount,
        lastScanFailureCount: lastScanFailureCount ?? this.lastScanFailureCount,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'name': name,
        'baseUrl': baseUrl,
        'rootPaths': rootPaths,
        if (rootRefs.isNotEmpty)
          'rootRefs': rootRefs.map((value) => value.toJson()).toList(),
        'enabled': enabled,
        'allowSelfSignedCertificate': allowSelfSignedCertificate,
        'lastScannedAt': lastScannedAt?.toIso8601String(),
        'scanStatus': scanStatus.name,
        'indexedVideoCount': indexedVideoCount,
        'matchedSubtitleCount': matchedSubtitleCount,
        'lastScanFailureCount': lastScanFailureCount,
      };

  @override
  bool operator ==(Object other) =>
      other is CloudSource &&
      other.id == id &&
      other.type == type &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      _listEquals(other.rootPaths, rootPaths) &&
      _listEquals(other.rootRefs, rootRefs) &&
      other.enabled == enabled &&
      other.allowSelfSignedCertificate == allowSelfSignedCertificate &&
      other.lastScannedAt == lastScannedAt &&
      other.scanStatus == scanStatus &&
      other.indexedVideoCount == indexedVideoCount &&
      other.matchedSubtitleCount == matchedSubtitleCount &&
      other.lastScanFailureCount == lastScanFailureCount;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        name,
        baseUrl,
        Object.hashAll(rootPaths),
        Object.hashAll(rootRefs),
        enabled,
        allowSelfSignedCertificate,
        lastScannedAt,
        scanStatus,
        indexedVideoCount,
        matchedSubtitleCount,
        lastScanFailureCount,
      );

  static bool _listEquals<T>(List<T> first, List<T> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
