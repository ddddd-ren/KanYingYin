import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_resource_name_cleaner.dart';

void main() {
  const cleaner = TmdbResourceNameCleaner();

  test('清除常见视频片源编码 HDR 和音频标签', () {
    final cases = <String, String>{
      '电影.2160p.WEB-DL.DV.HDR10+.x265.TrueHD.7.1.Atmos.mkv': '电影',
      '电影 1080p BluRay VC-1 DTS-HD MA 5.1.m2ts': '电影',
      '电影_720p_WEBRip_VP9_Opus.webm': '电影',
      '电影.DVDRip.XviD.AC3.avi': '电影',
      '电影 4K REMUX H.265 EAC3 DD+ DDP5.1.mkv': '电影',
      '电影 8K UHD AV1 HLG SDR LPCM PCM Vorbis ALAC.mkv': '电影',
    };

    for (final entry in cases.entries) {
      expect(cleaner.clean(entry.key), entry.value, reason: entry.key);
    }
  });

  test('只清除名称末尾的已知视频和音频扩展名', () {
    for (final name in <String>[
      '电影.mp4',
      '电影.mkv',
      '电影.mka',
      '电影.flac',
    ]) {
      expect(cleaner.clean(name), '电影', reason: name);
    }
    expect(cleaner.clean('REC.unknown'), 'REC unknown');
  });

  test('保留正式括号标题数字标题和未知发布文字', () {
    expect(cleaner.clean('[REC] (2007).mkv'), '[REC] (2007)');
    expect(cleaner.clean('1923.mkv'), '1923');
    expect(cleaner.clean('The 100.mkv'), 'The 100');
    expect(cleaner.clean('作品【导演收藏】.mkv'), '作品【导演收藏】');
  });
}
