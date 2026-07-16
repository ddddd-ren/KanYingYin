import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  group('MediaRecognitionSettings', () {
    test('存储缺失时使用本地与云端默认值', () {
      final settings = MediaRecognitionSettings(storage: _MemoryStorage());

      expect(
        settings.localMinSizeBytes,
        MediaRecognitionSettings.localDefaultBytes,
      );
      expect(
        settings.cloudMinSizeBytes,
        MediaRecognitionSettings.cloudDefaultBytes,
      );
    });

    test('本地与云端大小分别保存且互不影响', () async {
      final storage = _MemoryStorage();
      final settings = MediaRecognitionSettings(storage: storage);

      await settings.saveMegabytes(MediaRecognitionTarget.local, 800);
      await settings.saveMegabytes(MediaRecognitionTarget.cloud, 10);

      expect(
        storage.values[SettingBoxKey.localMinRecognizedVideoSizeBytes],
        800 * MediaRecognitionSettings.bytesPerMegabyte,
      );
      expect(
        storage.values[SettingBoxKey.cloudMinRecognizedVideoSizeBytes],
        10 * MediaRecognitionSettings.bytesPerMegabyte,
      );
      expect(
        settings.localMinSizeBytes,
        800 * MediaRecognitionSettings.bytesPerMegabyte,
      );
      expect(
        settings.cloudMinSizeBytes,
        10 * MediaRecognitionSettings.bytesPerMegabyte,
      );
    });

    test('格式化不限制与 GB 整倍数', () {
      expect(MediaRecognitionSettings.formatMegabytes(0), '不限制');
      expect(MediaRecognitionSettings.formatMegabytes(1024), '1 GB');
      expect(MediaRecognitionSettings.formatMegabytes(2048), '2 GB');
      expect(MediaRecognitionSettings.formatMegabytes(800), '800 MB');
    });

    test('拒绝负数与超过 1 TB 的 MB 值', () {
      expect(
        () => MediaRecognitionSettings.validateMegabytes(-1),
        throwsFormatException,
      );
      expect(
        () => MediaRecognitionSettings.validateMegabytes(1048577),
        throwsFormatException,
      );
      expect(MediaRecognitionSettings.validateMegabytes(0), 0);
      expect(MediaRecognitionSettings.validateMegabytes(1048576), 1048576);
    });

    test('错误类型、负数与超过上限的字节值回退默认值', () {
      final storage = _MemoryStorage({
        SettingBoxKey.localMinRecognizedVideoSizeBytes: '800',
        SettingBoxKey.cloudMinRecognizedVideoSizeBytes: -1,
      });
      final settings = MediaRecognitionSettings(storage: storage);

      expect(
        settings.localMinSizeBytes,
        MediaRecognitionSettings.localDefaultBytes,
      );
      expect(
        settings.cloudMinSizeBytes,
        MediaRecognitionSettings.cloudDefaultBytes,
      );

      storage.values[SettingBoxKey.localMinRecognizedVideoSizeBytes] =
          MediaRecognitionSettings.maxMegabytes *
                  MediaRecognitionSettings.bytesPerMegabyte +
              1;
      expect(
        settings.localMinSizeBytes,
        MediaRecognitionSettings.localDefaultBytes,
      );
    });

    test('字节安全转换为完整 MB 并对无效值使用回退值', () {
      expect(
        MediaRecognitionSettings.bytesToMegabytes(
          10 * MediaRecognitionSettings.bytesPerMegabyte,
        ),
        10,
      );
      expect(MediaRecognitionSettings.bytesToMegabytes(-1, fallback: 800), 800);
      expect(
        MediaRecognitionSettings.bytesToMegabytes(
          MediaRecognitionSettings.maxMegabytes *
                  MediaRecognitionSettings.bytesPerMegabyte +
              1,
          fallback: 1,
        ),
        1,
      );
    });

    test('预设值保持稳定', () {
      expect(MediaRecognitionSettings.presetMegabytes, [
        0,
        1,
        10,
        50,
        100,
        500,
        800,
        1024,
      ]);
    });
  });
}

class _MemoryStorage implements RecognitionSettingsStorage {
  _MemoryStorage([Map<String, Object?>? initialValues])
      : values = {...?initialValues};

  final Map<String, Object?> values;

  @override
  Object? read(String key) => values[key];

  @override
  Future<void> write(String key, int value) async {
    values[key] = value;
  }
}
