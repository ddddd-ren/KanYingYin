import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';

abstract interface class ConfigurationUserDataStore {
  Future<PortableUserData> capture();
  Future<void> replace(PortableUserData data);
}

class SettingsConfigurationUserDataStore implements ConfigurationUserDataStore {
  const SettingsConfigurationUserDataStore(this.settings);
  final TypedSettings settings;

  @override
  Future<PortableUserData> capture() =>
      userDataMutationLock.synchronized(() async {
        final sources = settings.readRaw(SettingBoxKey.localMediaSources);
        final classificationMode =
            settings.readRaw(SettingBoxKey.mediaClassificationMode);
        final roots = <String>[];
        if (sources is List) {
          for (final source in sources.whereType<Map<Object?, Object?>>()) {
            final path = source['path'];
            if (path is String &&
                path.isNotEmpty &&
                !path.startsWith('content:')) {
              roots.add(path);
            }
          }
        }
        return PortableUserData.fromJson({
          'states': settings.readRaw(SettingBoxKey.mediaLibraryUserStates),
          'bookmarks': settings.readRaw(SettingBoxKey.playerBookmarks),
          'history': settings.readRaw(SettingBoxKey.playbackHistory),
          'localRoots': roots,
          'timelineSegments':
              settings.readRaw(SettingBoxKey.playerTimelineSegments),
          'watchStates': settings.readRaw(SettingBoxKey.mediaWatchStates),
          'trackPreferences':
              settings.readRaw(SettingBoxKey.trackSelectionPreferences),
          'preferredAudioLanguage':
              settings.readRaw(SettingBoxKey.preferredAudioLanguage),
          'preferredSubtitleLanguage':
              settings.readRaw(SettingBoxKey.preferredSubtitleLanguage),
          'classificationMode': const {'conservative', 'standard', 'manual'}
                  .contains(classificationMode)
              ? classificationMode
              : 'conservative',
        });
      });

  @override
  Future<void> replace(PortableUserData data) =>
      userDataMutationLock.synchronized(() async {
        final json = data.toJson();
        await settings.write(
            SettingBoxKey.mediaLibraryUserStates, json['states']);
        await settings.write(SettingBoxKey.playerBookmarks, json['bookmarks']);
        await settings.write(SettingBoxKey.playbackHistory, json['history']);
        await settings.write(
            SettingBoxKey.playerTimelineSegments, json['timelineSegments']);
        await settings.write(
            SettingBoxKey.mediaWatchStates, json['watchStates']);
        await settings.write(
            SettingBoxKey.trackSelectionPreferences, json['trackPreferences']);
        for (final key in [
          SettingBoxKey.preferredAudioLanguage,
          SettingBoxKey.preferredSubtitleLanguage
        ]) {
          if (json[key] == null) {
            await settings.delete(key);
          } else {
            await settings.write(key, json[key]);
          }
        }
        if (data.classificationMode != null) {
          await settings.write(
              SettingBoxKey.mediaClassificationMode, data.classificationMode);
        }
        PlayerTimelineSegmentRepository.changes.value++;
        MediaWatchStateRepository.changes.value++;
        MediaLibraryUserStateRepository.changes.value++;
      });
}
