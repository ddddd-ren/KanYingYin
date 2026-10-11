import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';

const subtitleOffPreference = TrackLanguageChoice(
    code: 'off',
    label: '关闭字幕',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.user);

String localWorkTrackPreferenceKey(String directoryId, String title) =>
    'local-work|$directoryId|${Uri.encodeComponent(title.trim().toLowerCase())}';

TrackLanguageChoice parseTrackPreference(Map<Object?, Object?> raw) {
  final code = raw['code'];
  final label = raw['label'];
  final kind = TrackLanguageKind.values
      .where((value) => value.name == raw['kind'])
      .firstOrNull;
  if (code is! String ||
      code.isEmpty ||
      code.length > 128 ||
      label is! String ||
      label.isEmpty ||
      label.length > 120 ||
      kind == null ||
      kind == TrackLanguageKind.unknown) {
    throw const FormatException('选轨偏好无效');
  }
  return TrackLanguageChoice(
      code: code, label: label, kind: kind, source: TrackLanguageSource.user);
}

TrackLanguageChoice? globalTrackPreference(
    String code, EmbeddedTrackType type) {
  if (code == 'auto') return null;
  if (code == 'off' && type == EmbeddedTrackType.subtitle) {
    return subtitleOffPreference;
  }
  final choice = commonTrackLanguageChoices
      .where((value) => value.code == code)
      .firstOrNull;
  return choice;
}

EmbeddedTrackInfo? selectTrackByPreferences(List<EmbeddedTrackInfo> tracks,
    {TrackLanguageChoice? series,
    TrackLanguageChoice? global,
    String? defaultTrackId}) {
  for (final choice in [series, global]) {
    if (choice == null) continue;
    if (choice.code == 'off') return null;
    final match = tracks
        .where((track) =>
            track.isLanguageResolved &&
            track.kind == choice.kind &&
            (choice.kind != TrackLanguageKind.other ||
                track.language.code == choice.code))
        .firstOrNull;
    if (match != null) return match;
  }
  return tracks.where((track) => track.id == defaultTrackId).firstOrNull;
}

class TrackSelectionPreferences {
  const TrackSelectionPreferences(this.storage);
  final PlayerBookmarkStorage storage;
  TrackLanguageChoice? load(String workKey, EmbeddedTrackType type,
      {Iterable<String> legacyWorkKeys = const <String>[]}) {
    final all = storage.read();
    for (final key in [workKey, ...legacyWorkKeys]) {
      final work = all is Map ? all[key] : null;
      final raw = work is Map ? work[type.name] : null;
      if (raw is! Map || raw['code'] is! String) continue;
      try {
        return parseTrackPreference(Map<Object?, Object?>.from(raw));
      } on Object {
        continue;
      }
    }
    return null;
  }

  Future<void> migrate(String workKey, Iterable<String> legacyWorkKeys) =>
      userDataMutationLock.synchronized(() async {
        if (workKey.isEmpty) return;
        final raw = storage.read();
        if (raw is! Map) return;
        final all = Map<String, Object?>.from(raw);
        final previous = all[workKey];
        final work = previous is Map
            ? Map<String, Object?>.from(previous)
            : <String, Object?>{};
        var changed = false;
        for (final type in EmbeddedTrackType.values) {
          if (load(workKey, type) != null) continue;
          for (final legacyKey in legacyWorkKeys) {
            final choice = load(legacyKey, type);
            if (choice == null) continue;
            work[type.name] = {
              'code': choice.code,
              'kind': choice.kind.name,
              'label': choice.label
            };
            changed = true;
            break;
          }
        }
        if (!changed) return;
        all[workKey] = work;
        await storage.write(all);
      });

  Future<void> save(String workKey, EmbeddedTrackInfo track) async {
    if (!track.isLanguageResolved || track.kind == TrackLanguageKind.unknown) {
      return;
    }
    await _save(workKey, track.type, track.language);
  }

  Future<void> saveSubtitleOff(String workKey) =>
      _save(workKey, EmbeddedTrackType.subtitle, subtitleOffPreference);
  Future<void> _save(
          String workKey, EmbeddedTrackType type, TrackLanguageChoice choice) =>
      userDataMutationLock.synchronized(() async {
        if (workKey.isEmpty) return;
        final raw = storage.read();
        final all =
            raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
        final previous = all[workKey];
        final work = previous is Map
            ? Map<String, Object?>.from(previous)
            : <String, Object?>{};
        work[type.name] = {
          'code': choice.code,
          'kind': choice.kind.name,
          'label': choice.label
        };
        all[workKey] = work;
        await storage.write(all);
      });
}
