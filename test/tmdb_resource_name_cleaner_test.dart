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
      '电影.2160p.x265.10bit.HDR.mkv': '电影',
    };

    for (final entry in cases.entries) {
      expect(cleaner.clean(entry.key), entry.value, reason: entry.key);
    }
  });

  test('清除 DSNP 和 HBOMax 平台及 BlackTV 发布后缀', () {
    final cases = <String, String>{
      '示例剧.1080p.DSNP.WEB-DL.AAC.2.0.H.264-BlackTV.mkv': '示例剧',
      '示例剧.1080p.HBOMax.WEB-DL.DDP2.0.H.264-BlackTV.mkv': '示例剧',
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

  test('清除发布站括号资源说明和系列编号前缀', () {
    final cases = <String, String>{
      '作品【高清剧集网发布 www.DDHDTV.com】[全46集][国语配音+中文字幕]': '作品',
      '作品【高清影视之家发布 www.SSDDSE.com】[高码版][国粤多音轨+中文字幕]': '作品',
      '034201_（系列）作品': '作品',
      '作品 全集4K日语中字': '作品',
      '作品 剧场版11部': '作品',
      '作品 1-2部合集 4K原盘 中文字幕': '作品',
    };

    for (final entry in cases.entries) {
      expect(cleaner.clean(entry.key), entry.value, reason: entry.key);
    }
  });

  test('新增发布规则不删除正式括号标题或数字作品名', () {
    expect(cleaner.clean('[REC] (2007).mkv'), '[REC] (2007)');
    expect(cleaner.clean('1923.mkv'), '1923');
    expect(cleaner.clean('The 100.mkv'), 'The 100');
    expect(cleaner.clean('作品【导演收藏】.mkv'), '作品【导演收藏】');
  });

  test('清除新增 REMUX 发布片段但保留正常短片名', () {
    const suffixes = <String>[
      'REMUX -HD MA TrueHD 7 1',
      'PROPER US REMUX -HD MA TrueHD 7 1',
      'UHD REMUX TrueHD7 1-DreamHD',
      'V4 UHD REMUX TrueHD7 1 Multi Audio-D',
      'V3 UHD REMUX DoVi TrueHD7 1 14Audio',
    ];
    for (final suffix in suffixes) {
      expect(
        cleaner.clean('流浪地球 $suffix.mkv'),
        '流浪地球',
        reason: suffix,
      );
    }
    expect(cleaner.clean('Us (2019).mkv'), 'Us (2019)');
    expect(cleaner.clean('V字仇杀队.mkv'), 'V字仇杀队');
  });

  test('清除方括号发布组和中英文音轨说明', () {
    expect(cleaner.clean('[DreamHD] 长安三万里 2023 2160p'), '长安三万里 2023');
    expect(cleaner.clean('地球脉动 III S01 4K 国英双语'), '地球脉动 III S01');
  });
}
