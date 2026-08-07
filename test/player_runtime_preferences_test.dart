import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/player/application/player_color_profile.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  late Directory directory;
  late Box<Object?> box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('player-runtime');
    Hive.init(directory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  setUp(() => box.clear());

  test('错误类型使用安全的播放器默认值', () async {
    await box.put(SettingBoxKey.defaultPlaySpeed, 'fast');
    await box.put(SettingBoxKey.hardwareDecoder, 42);
    final preferences = PlayerRuntimePreferences(TypedSettings(box));

    final value = preferences.load();

    expect(value.playSpeed, 1.0);
    expect(value.hardwareDecoder, isNotEmpty);
    expect(value.buttonSkipTime, 80);
    expect(value.arrowKeySkipTime, 10);
    expect(value.colorProfile, PlayerColorProfile.automatic);
  });

  test('播放器色彩方案使用强类型存储并安全回退', () async {
    final preferences = PlayerRuntimePreferences(TypedSettings(box));
    await box.put(
      SettingBoxKey.playerColorProfile,
      PlayerColorProfile.hdrToSdr.storageValue,
    );

    expect(preferences.load().colorProfile, PlayerColorProfile.hdrToSdr);

    await box.put(SettingBoxKey.playerColorProfile, 'invalid');
    expect(preferences.load().colorProfile, PlayerColorProfile.automatic);
  });

  test('保存跳转时间后下一次加载可见', () async {
    final preferences = PlayerRuntimePreferences(TypedSettings(box));

    await preferences.saveButtonSkipTime(45);
    await preferences.saveArrowKeySkipTime(8);

    expect(preferences.load().buttonSkipTime, 45);
    expect(preferences.load().arrowKeySkipTime, 8);
  });

  test('Android 独立读取解码器、渲染器和画中画设置', () async {
    await box.put(SettingBoxKey.hardwareDecoder, 'd3d11va-copy');
    await box.put(SettingBoxKey.androidHardwareDecoder, 'no');
    await box.put(SettingBoxKey.androidVideoRenderer, 'mediacodec_embed');
    await box.put(SettingBoxKey.androidAutoEnterPip, true);
    final preferences = PlayerRuntimePreferences(
      TypedSettings(box),
      capabilities: AppPlatformCapabilities.android,
    );

    final value = preferences.load();

    expect(value.hardwareDecoder, 'no');
    expect(value.videoRenderer, 'gpu');
    expect(value.anime4kSupported, isTrue);
    expect(value.androidAutoEnterPip, isTrue);
  });

  test('Windows 直通硬解附带对应拷贝模式作为自动回退', () async {
    await box.put(SettingBoxKey.hardwareDecoder, 'd3d11va');
    final preferences = PlayerRuntimePreferences(
      TypedSettings(box),
      capabilities: AppPlatformCapabilities.windows,
    );

    final value = preferences.load();

    expect(value.hardwareDecoder, 'd3d11va,d3d11va-copy');
    expect(value.hardwareAccelerationEnabled, isTrue);
  });

  test('Android 自动渲染器使用 media-kit 默认 GPU 并支持 Anime4K', () {
    final preferences = PlayerRuntimePreferences(
      TypedSettings(box),
      capabilities: AppPlatformCapabilities.android,
    );

    final value = preferences.load();

    expect(value.videoRenderer, isNull);
    expect(value.anime4kSupported, isTrue);
  });
}
