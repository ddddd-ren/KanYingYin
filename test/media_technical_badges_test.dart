import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';

void main() {
  const resolver = MediaTechnicalBadgeResolver();

  test('实际宽高优先并兼容竖屏，只显示一个最高档清晰度', () {
    expect(
      resolver.resolve(
        names: const ['误标.1080p.mkv'],
        videoWidth: 3840,
        videoHeight: 2160,
      ).map((item) => item.label),
      ['4K'],
    );
    expect(
      resolver.resolve(
        names: const ['竖屏视频.mkv'],
        videoWidth: 1440,
        videoHeight: 2560,
      ).map((item) => item.label),
      ['2K'],
    );
    expect(
      resolver.resolve(names: const ['电影.720p.mkv']),
      isEmpty,
    );
    expect(
      resolver.resolve(
        names: const ['误标.4K.mkv'],
        videoWidth: 1280,
        videoHeight: 720,
      ),
      isEmpty,
    );
  });

  test('识别杜比视界 HDR10+ HDR 和全景声并正确去重', () {
    expect(
      resolver.resolve(
        names: const [
          'Movie.2160p.DoVi.HDR10Plus.Dolby.Atmos.mkv',
        ],
      ).map((item) => item.label),
      ['4K', '杜比视界', 'HDR10+', '杜比全景声'],
    );
    expect(
      resolver.resolve(
          names: const ['Movie.1080p.HDR10.mkv']).map((item) => item.label),
      ['1080P', 'HDR'],
    );
  });

  test('作品汇总取最高清晰度并保留任一文件的影音规格', () {
    final result = resolver.aggregate([
      resolver.resolve(names: const ['E01.1080p.HDR.mkv']),
      resolver.resolve(names: const ['E02.2160p.DV.Atmos.mkv']),
    ]);
    expect(
      result.map((item) => item.label),
      ['4K', '杜比视界', 'HDR', '杜比全景声'],
    );
  });
}
