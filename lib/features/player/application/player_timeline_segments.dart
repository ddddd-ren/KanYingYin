import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';

enum PlayerSegmentKind { intro, outro }

class PlayerTimelineSegment {
  const PlayerTimelineSegment(
      {required this.kind, required this.start, required this.end});
  final PlayerSegmentKind kind;
  final Duration start;
  final Duration end;
  String get label => kind == PlayerSegmentKind.intro ? '片头' : '片尾';
  Map<String, Object> toJson() => {
        'kind': kind.name,
        'startMillis': start.inMilliseconds,
        'endMillis': end.inMilliseconds,
      };
  factory PlayerTimelineSegment.fromJson(Map<Object?, Object?> json) {
    final kind = PlayerSegmentKind.values
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    if (kind == null ||
        json['startMillis'] is! int ||
        json['endMillis'] is! int) {
      throw const FormatException('片头片尾区间格式无效');
    }
    return PlayerTimelineSegment(
        kind: kind,
        start: Duration(milliseconds: json['startMillis'] as int),
        end: Duration(milliseconds: json['endMillis'] as int));
  }
}

class PlayerTimelineSegmentRecord {
  const PlayerTimelineSegmentRecord(
      {required this.fingerprint,
      required this.duration,
      required this.segments});
  final String fingerprint;
  final Duration duration;
  final List<PlayerTimelineSegment> segments;
  bool matches(String fingerprint, Duration duration) =>
      this.fingerprint == fingerprint && this.duration == duration;
  Map<String, Object> toJson() => {
        'fingerprint': fingerprint,
        'durationMillis': duration.inMilliseconds,
        'segments': segments.map((segment) => segment.toJson()).toList(),
      };
  factory PlayerTimelineSegmentRecord.fromJson(Map<Object?, Object?> json) {
    final fingerprint = json['fingerprint'];
    final duration = json['durationMillis'];
    final raw = json['segments'];
    if (fingerprint is! String ||
        fingerprint.isEmpty ||
        fingerprint.length > 4096 ||
        duration is! int ||
        duration <= 0 ||
        duration > 2147483647 ||
        raw is! List ||
        raw.length > 2) {
      throw const FormatException('片头片尾记录无效');
    }
    final segments = raw.map((value) {
      if (value is! Map) throw const FormatException('片头片尾区间无效');
      return PlayerTimelineSegment.fromJson(Map<Object?, Object?>.from(value));
    }).toList();
    validatePlayerTimelineSegments(segments, Duration(milliseconds: duration));
    return PlayerTimelineSegmentRecord(
        fingerprint: fingerprint,
        duration: Duration(milliseconds: duration),
        segments: List.unmodifiable(segments));
  }
}

void validatePlayerTimelineSegments(
    List<PlayerTimelineSegment> segments, Duration duration) {
  if (duration <= Duration.zero ||
      duration.inMilliseconds > 2147483647 ||
      segments.length > 2 ||
      segments.map((segment) => segment.kind).toSet().length !=
          segments.length) {
    throw const FormatException('每个视频最多设置一段片头和一段片尾');
  }
  for (final segment in segments) {
    if (segment.start < Duration.zero ||
        segment.end <= segment.start ||
        segment.end > duration) {
      throw const FormatException('起点必须早于终点，且区间不能超过视频时长');
    }
  }
  final intro = segments
      .where((segment) => segment.kind == PlayerSegmentKind.intro)
      .firstOrNull;
  final outro = segments
      .where((segment) => segment.kind == PlayerSegmentKind.outro)
      .firstOrNull;
  if (intro != null && outro != null && intro.end > outro.start) {
    throw const FormatException('片头应在片尾之前，两个区间不能重叠');
  }
}

class PlayerTimelineSegmentRepository {
  PlayerTimelineSegmentRepository(this.storage);
  final PlayerBookmarkStorage storage;
  static final ValueNotifier<int> changes = ValueNotifier(0);
  PlayerTimelineSegmentRecord? load(String mediaKey) {
    final raw = storage.read();
    final record = raw is Map ? raw[mediaKey] : null;
    if (record is! Map) return null;
    try {
      return PlayerTimelineSegmentRecord.fromJson(
          Map<Object?, Object?>.from(record));
    } on Object {
      return null;
    }
  }

  List<PlayerTimelineSegment> visibleSegments(String mediaKey,
      {required String fingerprint, required Duration duration}) {
    final record = load(mediaKey);
    return record?.matches(fingerprint, duration) == true
        ? record!.segments
        : const [];
  }

  Future<void> save(String mediaKey,
          {required String fingerprint,
          required Duration duration,
          required List<PlayerTimelineSegment> segments}) =>
      userDataMutationLock.synchronized(() async {
        if (mediaKey.trim().isEmpty ||
            mediaKey.length > 4096 ||
            fingerprint.isEmpty ||
            fingerprint.length > 4096) {
          throw const FormatException('当前视频身份尚未就绪');
        }
        validatePlayerTimelineSegments(segments, duration);
        final raw = storage.read();
        final all =
            raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
        if (segments.isEmpty) {
          all.remove(mediaKey);
        } else {
          all[mediaKey] = PlayerTimelineSegmentRecord(
                  fingerprint: fingerprint,
                  duration: duration,
                  segments: List.unmodifiable(segments))
              .toJson();
        }
        await storage.write(all);
        changes.value++;
      });
}

Duration parsePlayerTimelineTime(String value) {
  final parts = value.trim().split(':');
  final numbers = parts.map(int.tryParse).toList();
  if (parts.isEmpty ||
      parts.length > 3 ||
      numbers.any((n) => n == null || n < 0) ||
      (parts.length > 1 && numbers.last! >= 60) ||
      (parts.length == 3 && numbers[1]! >= 60)) {
    throw const FormatException('请输入秒数、MM:SS 或 HH:MM:SS');
  }
  var seconds = 0;
  for (final number in numbers) {
    seconds = seconds * 60 + number!;
  }
  if (seconds > 2147483) throw const FormatException('时间超出范围');
  return Duration(seconds: seconds);
}

String formatPlayerTimelineTime(Duration value) =>
    '${value.inHours.toString().padLeft(2, '0')}:${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
