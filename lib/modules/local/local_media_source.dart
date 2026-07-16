import 'package:path/path.dart' as p;

class LocalMediaSource {
  final String id;
  final String path;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastScannedAt;
  final int fileCount;
  final int videoCount;
  final int directoryCount;
  final int skippedCount;
  final bool recursive;
  final bool enabled;

  const LocalMediaSource({
    required this.id,
    required this.path,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.lastScannedAt,
    this.fileCount = 0,
    this.videoCount = 0,
    this.directoryCount = 0,
    this.skippedCount = 0,
    this.recursive = false,
    this.enabled = true,
  });

  factory LocalMediaSource.fromPath(String path) {
    final normalizedPath = _normalizePath(path);
    final now = DateTime.now();
    return LocalMediaSource(
      id: idForPath(normalizedPath),
      path: normalizedPath,
      name: _nameForPath(normalizedPath),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory LocalMediaSource.fromJson(Map<String, dynamic> json) {
    final path = _stringValue(json['path']);
    return LocalMediaSource(
      id: _stringValue(json['id'], fallback: idForPath(path)),
      path: path,
      name: _stringValue(json['name'], fallback: _nameForPath(path)),
      createdAt: _dateValue(json['createdAt']) ?? DateTime.now(),
      updatedAt: _dateValue(json['updatedAt']) ?? DateTime.now(),
      lastScannedAt: _dateValue(json['lastScannedAt']),
      fileCount: _intValue(json['fileCount']),
      videoCount: _intValue(json['videoCount']),
      directoryCount: _intValue(json['directoryCount']),
      skippedCount: _intValue(json['skippedCount']),
      recursive: _boolValue(json['recursive']),
      enabled: _boolValue(json['enabled'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastScannedAt': lastScannedAt?.toIso8601String(),
      'fileCount': fileCount,
      'videoCount': videoCount,
      'directoryCount': directoryCount,
      'skippedCount': skippedCount,
      'recursive': recursive,
      'enabled': enabled,
    };
  }

  LocalMediaSource copyWith({
    String? path,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastScannedAt,
    int? fileCount,
    int? videoCount,
    int? directoryCount,
    int? skippedCount,
    bool? recursive,
    bool? enabled,
  }) {
    final nextPath = path == null ? this.path : _normalizePath(path);
    return LocalMediaSource(
      id: idForPath(nextPath),
      path: nextPath,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      fileCount: fileCount ?? this.fileCount,
      videoCount: videoCount ?? this.videoCount,
      directoryCount: directoryCount ?? this.directoryCount,
      skippedCount: skippedCount ?? this.skippedCount,
      recursive: recursive ?? this.recursive,
      enabled: enabled ?? this.enabled,
    );
  }

  static String idForPath(String path) {
    return _normalizePath(path).toLowerCase();
  }

  static String _normalizePath(String path) {
    return p.normalize(path.trim());
  }

  static String _nameForPath(String path) {
    final basename = p.basename(path);
    return basename.isEmpty ? path : basename;
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.isNotEmpty) return value;
    return fallback;
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static bool _boolValue(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    return fallback;
  }

  static DateTime? _dateValue(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
