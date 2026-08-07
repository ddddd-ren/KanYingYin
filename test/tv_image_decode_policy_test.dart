import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_image_decode_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android TV 海报和季度缩略图有上限，Windows 不限制', () {
    final tv = AppPlatformCapabilities.android.copyWith(
      television: true,
      androidSdkInt: 28,
    );

    expect(
      TvImageDecodePolicy.poster(tv, devicePixelRatio: 2),
      const TvImageDecodeSize(width: 720, height: 1080),
    );
    expect(
      TvImageDecodePolicy.seasonThumbnail(tv, devicePixelRatio: 2),
      const TvImageDecodeSize(width: 368, height: 552),
    );
    expect(
      TvImageDecodePolicy.poster(
        AppPlatformCapabilities.windows,
        devicePixelRatio: 2,
      ),
      isNull,
    );
  });
}
