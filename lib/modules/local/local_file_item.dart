import 'package:kanyingyin/modules/local/local_episode_info.dart';

enum LocalSortMode {
  name('name'),
  size('size'),
  modified('modified');

  const LocalSortMode(this.value);

  final String value;

  static LocalSortMode fromValue(String value) {
    return LocalSortMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => LocalSortMode.name,
    );
  }
}

class LocalScanResult {
  final String currentPath;
  final List<LocalFileItem> items;
  final int skippedCount;

  const LocalScanResult({
    required this.currentPath,
    required this.items,
    required this.skippedCount,
  });
}

class LocalFileItem {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final bool isDirectory;
  final bool isVideo;
  final String? cover;
  final String? subtitlePath;
  final Duration? duration;
  final int? videoWidth;
  final int? videoHeight;
  final LocalEpisodeInfo? episodeInfo;
  final String? releaseGroup;
  final String? resolution;
  final String? source;
  final String? codec;
  final String? seriesTitleOverride;

  const LocalFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.isDirectory,
    required this.isVideo,
    this.cover,
    this.subtitlePath,
    this.duration,
    this.videoWidth,
    this.videoHeight,
    this.episodeInfo,
    this.releaseGroup,
    this.resolution,
    this.source,
    this.codec,
    this.seriesTitleOverride,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toUpperCase() : '';
  }

  String get formattedSize {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedModified {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${modified.year}-${twoDigits(modified.month)}-${twoDigits(modified.day)}';
  }

  bool get hasSubtitle => subtitlePath != null && subtitlePath!.isNotEmpty;

  bool get hasEpisodeInfo => episodeInfo != null;

  bool get hasMediaInfo {
    return duration != null ||
        ((videoWidth ?? 0) > 0 && (videoHeight ?? 0) > 0);
  }

  String get formattedDuration {
    final value = duration;
    if (value == null || value <= Duration.zero) return '';
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  String get formattedResolution {
    final parsed = resolution;
    if (parsed != null && parsed.isNotEmpty) return parsed;
    final width = videoWidth ?? 0;
    final height = videoHeight ?? 0;
    if (width <= 0 || height <= 0) return '';
    return '${width}x$height';
  }

  LocalFileItem copyWith({
    String? path,
    String? name,
    int? size,
    DateTime? modified,
    bool? isDirectory,
    bool? isVideo,
    String? cover,
    String? subtitlePath,
    Duration? duration,
    int? videoWidth,
    int? videoHeight,
    LocalEpisodeInfo? episodeInfo,
    String? releaseGroup,
    String? resolution,
    String? source,
    String? codec,
    String? seriesTitleOverride,
  }) {
    return LocalFileItem(
      path: path ?? this.path,
      name: name ?? this.name,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      isDirectory: isDirectory ?? this.isDirectory,
      isVideo: isVideo ?? this.isVideo,
      cover: cover ?? this.cover,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      duration: duration ?? this.duration,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      episodeInfo: episodeInfo ?? this.episodeInfo,
      releaseGroup: releaseGroup ?? this.releaseGroup,
      resolution: resolution ?? this.resolution,
      source: source ?? this.source,
      codec: codec ?? this.codec,
      seriesTitleOverride: seriesTitleOverride ?? this.seriesTitleOverride,
    );
  }
}
