import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/utils/storage.dart';

String embeddedTrackLanguageFingerprint({
  required String mediaKey,
  required EmbeddedTrackType type,
  required String trackId,
  required String codec,
  required String title,
}) {
  final parts = <String>[
    mediaKey.trim(),
    type.name,
    trackId.trim(),
    codec.trim().toLowerCase(),
    title.trim(),
  ];
  return sha256.convert(utf8.encode(parts.join('\u0000'))).toString();
}

class EmbeddedTrackLanguagePreferences {
  EmbeddedTrackLanguagePreferences({Box<Object?>? storage})
      : _storage = storage ?? GStorage.setting;

  final Box<Object?> _storage;

  TrackLanguageChoice? load(String fingerprint) {
    if (fingerprint.trim().isEmpty) return null;
    final all = _storage.get(SettingBoxKey.embeddedTrackLanguageOverrides);
    if (all is! Map) return null;
    final raw = all[fingerprint];
    if (raw is! Map) return null;
    final code = raw['code'];
    final label = raw['label'];
    final kindName = raw['kind'];
    if (code is! String ||
        code.trim().isEmpty ||
        label is! String ||
        label.trim().isEmpty ||
        kindName is! String) {
      return null;
    }
    TrackLanguageKind? kind;
    for (final candidate in TrackLanguageKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    if (kind == null || kind == TrackLanguageKind.unknown) return null;
    return TrackLanguageChoice(
      code: code.trim(),
      label: label.trim(),
      kind: kind,
      source: TrackLanguageSource.user,
    );
  }

  Future<void> save(String fingerprint, TrackLanguageChoice choice) async {
    if (fingerprint.trim().isEmpty ||
        choice.code.trim().isEmpty ||
        choice.label.trim().isEmpty ||
        !choice.isResolved) {
      return;
    }
    final current = _storage.get(SettingBoxKey.embeddedTrackLanguageOverrides);
    final values = <String, Object?>{
      if (current is Map)
        for (final entry in current.entries) entry.key.toString(): entry.value,
    };
    values[fingerprint] = <String, Object?>{
      'code': choice.code.trim(),
      'label': choice.label.trim(),
      'kind': choice.kind.name,
      'confirmedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _storage.put(
      SettingBoxKey.embeddedTrackLanguageOverrides,
      values,
    );
  }
}
