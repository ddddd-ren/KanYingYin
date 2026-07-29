import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:path/path.dart' as p;

class LocalMediaSource {
  final String id;
  final MediaLocation location;
  String get path => location.value;
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
    required this.location,
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
    return LocalMediaSource.fromLocation(MediaLocation.file(path));
  }

  factory LocalMediaSource.fromLocation(
    MediaLocation location, {
    String? displayName,
  }) {
    final now = DateTime.now();
    return LocalMediaSource(
      id: location.stableId,
      location: location,
      name: displayName ?? _nameForLocation(location),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory LocalMediaSource.fromJson(Map<String, dynamic> json) {
    final path = _stringValue(json['path']);
    final rawLocation = json['location'];
    final location = rawLocation is Map
        ? MediaLocation.fromJson(Map<Object?, Object?>.from(rawLocation))
        : MediaLocation.file(path);
    return LocalMediaSource(
      id: location.stableId,
      location: location,
      name: _stringValue(json['name'], fallback: _nameForLocation(location)),
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
      'location': location.toJson(),
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
    MediaLocation? location,
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
    final nextLocation = location ?? this.location;
    return LocalMediaSource(
      id: nextLocation.stableId,
      location: nextLocation,
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
    return MediaLocation.file(path).stableId;
  }

  static String idForLocation(MediaLocation location) => location.stableId;

  static String _nameForLocation(MediaLocation location) {
    if (location.isDocument) return location.value;
    return _nameForPath(location.value);
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
