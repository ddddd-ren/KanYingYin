import 'package:flutter/foundation.dart';

enum MediaNodeRole {
  work,
  season,
  episode,
  version,
  advertisement,
  unknown,
}

@immutable
class MediaReleaseTags {
  const MediaReleaseTags({
    this.resolution,
    this.bitrate,
    this.source,
    this.codec,
    this.dynamicRange = const <String>[],
    this.audio = const <String>[],
    this.subtitles = const <String>[],
    this.releaseGroup,
  });

  factory MediaReleaseTags.fromJson(Map<String, Object?> json) {
    return MediaReleaseTags(
      resolution: _stringOrNull(json['resolution']),
      bitrate: _stringOrNull(json['bitrate']),
      source: _stringOrNull(json['source']),
      codec: _stringOrNull(json['codec']),
      dynamicRange: _stringList(json['dynamicRange']),
      audio: _stringList(json['audio']),
      subtitles: _stringList(json['subtitles']),
      releaseGroup: _stringOrNull(json['releaseGroup']),
    );
  }

  final String? resolution;
  final String? bitrate;
  final String? source;
  final String? codec;
  final List<String> dynamicRange;
  final List<String> audio;
  final List<String> subtitles;
  final String? releaseGroup;

  MediaReleaseTags copyWith({
    String? resolution,
    String? bitrate,
    String? source,
    String? codec,
    List<String>? dynamicRange,
    List<String>? audio,
    List<String>? subtitles,
    String? releaseGroup,
  }) {
    return MediaReleaseTags(
      resolution: resolution ?? this.resolution,
      bitrate: bitrate ?? this.bitrate,
      source: source ?? this.source,
      codec: codec ?? this.codec,
      dynamicRange: dynamicRange ?? this.dynamicRange,
      audio: audio ?? this.audio,
      subtitles: subtitles ?? this.subtitles,
      releaseGroup: releaseGroup ?? this.releaseGroup,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (resolution != null) 'resolution': resolution,
        if (bitrate != null) 'bitrate': bitrate,
        if (source != null) 'source': source,
        if (codec != null) 'codec': codec,
        if (dynamicRange.isNotEmpty) 'dynamicRange': dynamicRange,
        if (audio.isNotEmpty) 'audio': audio,
        if (subtitles.isNotEmpty) 'subtitles': subtitles,
        if (releaseGroup != null) 'releaseGroup': releaseGroup,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MediaReleaseTags &&
            resolution == other.resolution &&
            bitrate == other.bitrate &&
            source == other.source &&
            codec == other.codec &&
            listEquals(dynamicRange, other.dynamicRange) &&
            listEquals(audio, other.audio) &&
            listEquals(subtitles, other.subtitles) &&
            releaseGroup == other.releaseGroup;
  }

  @override
  int get hashCode => Object.hash(
        resolution,
        bitrate,
        source,
        codec,
        Object.hashAll(dynamicRange),
        Object.hashAll(audio),
        Object.hashAll(subtitles),
        releaseGroup,
      );

  static String? _stringOrNull(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }
}

@immutable
class MediaNameAnalysis {
  const MediaNameAnalysis({
    required this.originalName,
    required this.role,
    this.titleCandidates = const <String>[],
    this.seasonNumber,
    this.episodeNumber,
    this.episodeEndNumber,
    this.year,
    this.releaseTags = const MediaReleaseTags(),
    this.confidence = 0,
    this.evidence = const <String>[],
  });

  final String originalName;
  final MediaNodeRole role;
  final List<String> titleCandidates;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? episodeEndNumber;
  final int? year;
  final MediaReleaseTags releaseTags;
  final double confidence;
  final List<String> evidence;
}
