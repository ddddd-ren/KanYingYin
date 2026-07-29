import 'dart:collection';

import 'package:media_kit/media_kit.dart';

enum PlayerDecoderFailureKind { audio, video, unknown }

class PlayerDecoderRecoveryPolicy {
  PlayerDecoderRecoveryPolicy({
    this.correlationWindow = const Duration(seconds: 2),
    this.reportWindow = const Duration(seconds: 1),
  });

  final Duration correlationWindow;
  final Duration reportWindow;
  final Queue<_DecoderLogRecord> _decoderLogs = Queue<_DecoderLogRecord>();
  final Map<String, DateTime> _reportedErrors = <String, DateTime>{};

  void recordLog(PlayerLog log, {DateTime? now}) {
    if (log.level.toLowerCase() != 'error') return;
    final kind = switch (log.prefix.toLowerCase()) {
      'ad' => PlayerDecoderFailureKind.audio,
      'vd' => PlayerDecoderFailureKind.video,
      _ => PlayerDecoderFailureKind.unknown,
    };
    if (kind == PlayerDecoderFailureKind.unknown) return;
    final timestamp = now ?? DateTime.now();
    _pruneDecoderLogs(timestamp);
    _decoderLogs.add(
      _DecoderLogRecord(
        kind: kind,
        text: _normalize(log.text),
        timestamp: timestamp,
      ),
    );
  }

  PlayerDecoderFailureKind classify(String error, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    _pruneDecoderLogs(timestamp);
    final normalized = _normalize(error);
    for (final record in _decoderLogs.toList().reversed) {
      if (record.text == normalized) return record.kind;
    }
    return PlayerDecoderFailureKind.unknown;
  }

  bool shouldReport(String error, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final normalized = _normalize(error);
    _reportedErrors.removeWhere(
      (_, reportedAt) => timestamp.difference(reportedAt) >= reportWindow,
    );
    final reportedAt = _reportedErrors[normalized];
    if (reportedAt != null && timestamp.difference(reportedAt) < reportWindow) {
      return false;
    }
    _reportedErrors[normalized] = timestamp;
    return true;
  }

  void reset() {
    _decoderLogs.clear();
    _reportedErrors.clear();
  }

  void _pruneDecoderLogs(DateTime now) {
    while (_decoderLogs.isNotEmpty &&
        now.difference(_decoderLogs.first.timestamp) >= correlationWindow) {
      _decoderLogs.removeFirst();
    }
  }

  String _normalize(String value) => value.trim().toLowerCase();
}

class _DecoderLogRecord {
  const _DecoderLogRecord({
    required this.kind,
    required this.text,
    required this.timestamp,
  });

  final PlayerDecoderFailureKind kind;
  final String text;
  final DateTime timestamp;
}
