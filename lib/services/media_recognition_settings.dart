import 'package:kanyingyin/utils/storage.dart';

enum MediaRecognitionTarget { local, cloud }

abstract interface class RecognitionSettingsStorage {
  Object? read(String key);

  Future<void> write(String key, int value);
}

class HiveRecognitionSettingsStorage implements RecognitionSettingsStorage {
  const HiveRecognitionSettingsStorage();

  @override
  Object? read(String key) => GStorage.setting.get(key);

  @override
  Future<void> write(String key, int value) async {
    await GStorage.setting.put(key, value);
  }
}

class MediaRecognitionSettings {
  MediaRecognitionSettings({RecognitionSettingsStorage? storage})
      : _storage = storage ?? const HiveRecognitionSettingsStorage();

  static const int bytesPerMegabyte = 1024 * 1024;
  static const int maxMegabytes = 1048576;
  static const int localDefaultBytes = 800 * bytesPerMegabyte;
  static const int cloudDefaultBytes = bytesPerMegabyte;
  static const List<int> presetMegabytes = [
    0,
    1,
    10,
    50,
    100,
    500,
    800,
    1024,
  ];

  static const int _maxBytes = maxMegabytes * bytesPerMegabyte;

  final RecognitionSettingsStorage _storage;

  int get localMinSizeBytes => _readBytes(
        SettingBoxKey.localMinRecognizedVideoSizeBytes,
        localDefaultBytes,
      );

  int get cloudMinSizeBytes => _readBytes(
        SettingBoxKey.cloudMinRecognizedVideoSizeBytes,
        cloudDefaultBytes,
      );

  Future<void> saveMegabytes(
    MediaRecognitionTarget target,
    int value,
  ) async {
    final megabytes = validateMegabytes(value);
    final key = switch (target) {
      MediaRecognitionTarget.local =>
        SettingBoxKey.localMinRecognizedVideoSizeBytes,
      MediaRecognitionTarget.cloud =>
        SettingBoxKey.cloudMinRecognizedVideoSizeBytes,
    };
    await _storage.write(key, megabytes * bytesPerMegabyte);
  }

  static int validateMegabytes(int value) {
    if (value < 0 || value > maxMegabytes) {
      throw FormatException('媒体识别大小必须在 0 到 $maxMegabytes MB 之间');
    }
    return value;
  }

  static String formatMegabytes(int value) {
    final megabytes = validateMegabytes(value);
    if (megabytes == 0) {
      return '不限制';
    }
    if (megabytes % 1024 == 0) {
      return '${megabytes ~/ 1024} GB';
    }
    return '$megabytes MB';
  }

  static int bytesToMegabytes(int bytes, {int fallback = 0}) {
    if (bytes < 0 || bytes > _maxBytes) {
      return validateMegabytes(fallback);
    }
    return bytes ~/ bytesPerMegabyte;
  }

  int _readBytes(String key, int fallback) {
    final value = _storage.read(key);
    if (value is! int || value < 0 || value > _maxBytes) {
      return fallback;
    }
    return value;
  }
}
