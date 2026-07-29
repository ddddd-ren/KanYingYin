import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  const parser = CloudMediaNameParser();

  test('单集名称识别标题、季号、集号和电视剧类型', () {
    final draft = parser.parse(
      originalName: 'Alice in Borderland S01E01.mkv',
      isDirectory: false,
    );

    expect(draft.originalName, 'Alice in Borderland S01E01.mkv');
    expect(draft.searchTitle, 'Alice in Borderland');
    expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
    expect(draft.seasonNumber, 1);
    expect(draft.episodeNumber, 1);
    expect(draft.year, isNull);
  });

  test('发布标签被清理且括号年份被结构化', () {
    final draft = parser.parse(
      originalName: '弥留之国的爱丽丝 (2020) 2160p WEB-DL x265 HDR 全8集',
      isDirectory: true,
    );

    expect(draft.searchTitle, '弥留之国的爱丽丝');
    expect(draft.year, 2020);
  });

  test('画质编码和杜比声道尾缀不进入 TMDB 搜索词', () {
    final draft = parser.parse(
      originalName: '流浪地球2.2160p WEB-DL HEVC DDP 5.1.mkv',
      isDirectory: false,
    );

    expect(draft.searchTitle, '流浪地球2');
  });

  test('完整发布标签不会进入网盘 TMDB 搜索词', () {
    final draft = parser.parse(
      originalName: '流浪地球2.2160p.REMUX.DV.HDR10+.H.265.TrueHD.7.1.Atmos.mkv',
      isDirectory: false,
    );

    expect(draft.searchTitle, '流浪地球2');
  });

  test('自定义剧名优先但季集仍从原名称识别', () {
    final draft = parser.parse(
      originalName: 'Alice.in.Borderland.S02E03.1080p.mkv',
      isDirectory: false,
      preferredTitle: '弥留之国的爱丽丝',
    );

    expect(draft.searchTitle, '弥留之国的爱丽丝');
    expect(draft.seasonNumber, 2);
    expect(draft.episodeNumber, 3);
  });

  test('目录季度后缀不会进入 TMDB 搜索词', () {
    final draft = parser.parse(
      originalName: '三体 Season 2',
      isDirectory: true,
    );

    expect(draft.searchTitle, '三体');
    expect(draft.seasonNumber, 2);
    expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
  });

  test('只删除已知发布标签并保留正式括号标题', () {
    final rec = parser.parse(
      originalName: '[REC] (2007).mkv',
      isDirectory: false,
    );
    final release = parser.parse(
      originalName: '作品【字幕组】[WEB-DL] 1080p.mkv',
      isDirectory: false,
    );

    expect(rec.searchTitle, '[REC]');
    expect(rec.year, 2007);
    expect(release.searchTitle, '作品');
  });

  test('未知名称不猜测结构字段', () {
    final draft = parser.parse(
      originalName: 'Untitled Video.mkv',
      isDirectory: false,
    );

    expect(draft.searchTitle, 'Untitled Video');
    expect(draft.year, isNull);
    expect(draft.seasonNumber, isNull);
    expect(draft.episodeNumber, isNull);
  });

  test('用户提供的发布前后缀只保留片名和结构化信息', () {
    final cases = <({String name, int? year, int? season})>[
      (
        name: '片名【日剧】全52集.国语配音+字.珍藏版.1996.1080P',
        year: 1996,
        season: null,
      ),
      (
        name:
            '片名.2008.Eng.Fre.Ger.Ita.Por.Spa.Cze.Hun.Pol.Rus.Tha.Jpn.2160p.BluRay.Hybrid.Remux.DV.HDR.HEVC.DTS-HD.MA-SGF',
        year: 2008,
        season: null,
      ),
      (
        name:
            '片名【高清剧集网发布 www.DDHDTV.com】[全46集][国语配音+中文字幕].S01.2006.1080p.Hami.WEB-DL.H264.AAC-LeloveTV',
        year: 2006,
        season: 1,
      ),
      (name: '片名 剧场版11部', year: null, season: null),
      (
        name:
            '片名【高清剧集网发布 www.PTHDTV.com】[全12集][简繁英字幕].S01.1080p.HBOMax.WEB-DL.DDP2.0.H.264-BlackTV',
        year: null,
        season: 1,
      ),
      (name: '片名 全集4K日语中字', year: null, season: null),
      (name: '034201_（系列）片名', year: null, season: null),
      (
        name:
            '片名【高清影视之家发布 www.SSDDSE.com】[高码版][国粤多音轨+中文字幕].2016.2160p.HQ.WEB-DL.H265.DTS5.1-DreamHD',
        year: 2016,
        season: null,
      ),
      (
        name:
            '片名【高清剧集网 www.BTHDTV.com】[全30集][国语配音+中文字幕].2005.4K.WEB-DL.H265.AAC-HotWEB',
        year: 2005,
        season: null,
      ),
      (
        name: '片名[全16集][中文字幕].S01.2160p.TVING.WEB-DL.H265.AAC-ColorTV',
        year: null,
        season: 1,
      ),
      (
        name:
            '片名【高清剧集网发布 www.DDHDTV.com】[全52集][国语配音+中文字幕].1997.1080p.KKTV.WEB-DL.H264.AAC-Huawei',
        year: 1997,
        season: null,
      ),
      (
        name:
            '片名【高清剧集网发布 www.DDHDTV.com】第二季[全6集][简繁英字幕].S02.2014.1080p.BluRay.x264.FLAC.2.0-ZeroTV',
        year: 2014,
        season: 2,
      ),
      (
        name:
            '片名【高清影视之家发布 www.SSDDSE.com】[高码版][国粤多音轨+中文字幕].2012.2160p.HQ.WEB-DL.H265.DTS5.1.2Audio-DreamHD',
        year: 2012,
        season: null,
      ),
      (
        name: '片名.2012.PROPER.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.5.1-FGT',
        year: 2012,
        season: null,
      ),
      (
        name:
            '片名【高清剧集网发布 www.DDHDTV.com】第一季[全6集][中文字幕].S01.BluRay.1080p.DTS-HDMA2.0.x264-BlackTV',
        year: null,
        season: 1,
      ),
      (
        name:
            '片名.2005.Eng.Fre.Ger.Ita.Por.Spa.Cze.Hun.Pol.Rus.Tha.Tur.Chi.Jpn.2160p.BluRay.Hybrid.Remux.DV.HDR.HEVC.DTS-HD.MA-SGF',
        year: 2005,
        season: null,
      ),
      (name: '片名 1-2部合集 4K原盘 中文字幕', year: null, season: null),
      (
        name:
            '片名【高清剧集网发布 www.PTHDTV.com】[全10集][简繁英字幕].S01.2160p.NF.WEB-DL.DDP5.1.Atmos.H.265-BlackTV',
        year: null,
        season: 1,
      ),
      (
        name:
            '片名【高清剧集网 www.BTHDTV.com】第五季[杜比视界版本][全6集][简繁英字幕].S05.2019.NF.WEB-DL.2160p.HEVC.DV.DDP-Xiaomi',
        year: 2019,
        season: 5,
      ),
      (
        name:
            '片名【高清剧集网发布 www.DDHDTV.com】第三季[全6集][简繁英字幕].S03.2016.1080p.BluRay.x264.DTS-ZeroTV',
        year: 2016,
        season: 3,
      ),
      (
        name:
            '片名【高清剧集网发布 www.DDHDTV.com】第四季[全6集][简繁英字幕].S04.2017.1080p.BluRay.x264.DTS-ZeroTV',
        year: 2017,
        season: 4,
      ),
      (
        name:
            '片名【高清剧集网发布 www.QQHDTV.com】第六季[全6集][简繁英字幕].S06.2160p.NF.WEB-DL.DDP5.1.Atmos.HEVC-ColorTV',
        year: null,
        season: 6,
      ),
    ];

    for (final item in cases) {
      final draft = parser.parse(
        originalName: item.name,
        isDirectory: true,
      );
      expect(draft.searchTitle, '片名', reason: item.name);
      expect(draft.year, item.year, reason: item.name);
      expect(draft.seasonNumber, item.season, reason: item.name);
      expect(
        draft.mediaTypeMode,
        item.season == null ? TmdbMediaTypeMode.auto : TmdbMediaTypeMode.tv,
        reason: item.name,
      );
    }
  });
}
