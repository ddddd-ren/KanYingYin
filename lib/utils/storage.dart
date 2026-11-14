// ignore_for_file: avoid_print

import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/legacy_history_data_cleaner.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/settings_box_recovery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kanyingyin/legacy/hive/legacy_bangumi_tag_adapter.dart';
import 'package:kanyingyin/legacy/hive/legacy_playback_media_item_adapter.dart';
import 'package:kanyingyin/utils/app_identity.dart';

export 'package:kanyingyin/features/settings/application/typed_settings.dart'
    show SettingBoxKey;

class GStorage {
  static late final Box<Object?> setting;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  static Future<void> init({String? hivePath}) async {
    _hivePath = hivePath ??
        '${(await getApplicationSupportDirectory()).path}/${AppIdentity.storageNamespace}/hive';

    try {
      await LegacyHistoryDataCleaner.deleteFrom(Directory(_hivePath!));
    } catch (error, stackTrace) {
      AppLogger().w(
        'GStorage: failed to delete legacy history data',
        error: error,
        stackTrace: stackTrace,
      );
    }

    Hive.registerAdapter(LegacyPlaybackMediaItemAdapter());
    Hive.registerAdapter(LegacyBangumiTagAdapter());

    setting = await openSettingsBoxSafely(
      file: File('$_hivePath/setting.hive'),
      // Hive 默认会截断损坏文件；备份完成前必须禁用隐式恢复。
      open: () => Hive.openBox<Object?>(
        'setting',
        path: _hivePath,
        crashRecovery: false,
      ),
    );
  }

  // Prevent instantiation
  GStorage._();
}

extension TypedSettingsBox on Box<Object?> {
  T getTyped<T>(Object? key, {required T defaultValue}) {
    final value = get(key, defaultValue: defaultValue);
    return value is T ? value : defaultValue;
  }

  List<T> getTypedList<T>(Object? key, {required List<T> defaultValue}) {
    final value = get(key, defaultValue: defaultValue);
    if (value is! List<Object?>) return defaultValue;
    final typedValues = value.whereType<T>().toList();
    return typedValues.length == value.length ? typedValues : defaultValue;
  }
}
