import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/media_name_analyzer.dart';

void main() {
  const analyzer = MediaNameAnalyzer();

  group('MediaNameAnalyzer', () {
    test('带发布规格的季度目录不产生剧名', () {
      final first = analyzer.analyze(
        '第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos',
        isDirectory: true,
      );
      final second = analyzer.analyze(
        '第三季（2025）4K DV&HDR',
        isDirectory: true,
      );

      expect(first.role, MediaNodeRole.season);
      expect(first.seasonNumber, 3);
      expect(first.titleCandidates, isEmpty);
      expect(first.releaseTags.resolution, '2160p');
      expect(first.releaseTags.source, 'Web-DL');
      expect(first.releaseTags.codec, 'H265');
      expect(
          first.releaseTags.audio, containsAll(<String>['DDP 5.1', 'Atmos']));
      expect(second.role, MediaNodeRole.season);
      expect(second.seasonNumber, 3);
      expect(second.year, 2025);
      expect(second.titleCandidates, isEmpty);
      expect(
        second.releaseTags.dynamicRange,
        containsAll(<String>['DV', 'HDR']),
      );
    });

    test('高码率等画质分层目录不作为作品名', () {
      for (final name in <String>['高码率', '低码率', '原画', '超清']) {
        expect(
          analyzer.isTransparentDirectoryName(name),
          isTrue,
          reason: name,
        );
      }
    });

    test('组合画质字幕和全季目录只产生版本标签', () {
      for (final (name, resolution, bitrate, subtitle)
          in <(String, String?, String?, String?)>[
        ('4K 高码率', '4K', '高码率', null),
        ('【全9集】【1080P】【内封简繁英】', '1080p', null, '内封简繁英'),
        ('【全9集】【1080P】【内嵌中字】', '1080p', null, '内嵌中字'),
      ]) {
        final analysis = analyzer.analyze(name, isDirectory: true);

        expect(
          analyzer.isTransparentDirectoryName(name),
          isTrue,
          reason: name,
        );
        expect(analysis.titleCandidates, isEmpty, reason: name);
        expect(analysis.releaseTags.resolution, resolution, reason: name);
        expect(analysis.releaseTags.bitrate, bitrate, reason: name);
        expect(
          analysis.releaseTags.subtitles,
          subtitle == null ? isEmpty : <String>[subtitle],
          reason: name,
        );
      }
    });

    test('纯数字和常见集号文件只输出集号证据', () {
      final cases = <String, int>{
        '006.mkv': 6,
        'E02.mkv': 2,
        'EP05.mkv': 5,
        'Episode 03.mkv': 3,
        '第4集.mkv': 4,
      };

      for (final entry in cases.entries) {
        final result = analyzer.analyze(entry.key, isDirectory: false);
        expect(result.role, MediaNodeRole.episode, reason: entry.key);
        expect(result.episodeNumber, entry.value, reason: entry.key);
        expect(result.titleCandidates, isEmpty, reason: entry.key);
      }
    });

    test('完整分集文件提取标题季集和发布规格', () {
      final result = analyzer.analyze(
        'Alice.in.Borderland.S03E01.2160p.WEB-DL.H265.DV.HDR.DDP5.1.Atmos.mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.episode);
      expect(result.titleCandidates, contains('Alice in Borderland'));
      expect(result.seasonNumber, 3);
      expect(result.episodeNumber, 1);
      expect(result.releaseTags.resolution, '2160p');
      expect(result.releaseTags.source, 'Web-DL');
      expect(result.releaseTags.codec, 'H265');
      expect(result.releaseTags.dynamicRange, <String>['DV', 'HDR']);
      expect(result.releaseTags.audio, <String>['DDP 5.1', 'Atmos']);
    });

    test('方括号发布名过滤音轨位深和校验码', () {
      final result = analyzer.analyze(
        '[KRL][Kamen Rider OOO][01][BDRip][1080P][x265_AC3][Main10][9F632FDD].mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.episode);
      expect(result.titleCandidates, <String>['Kamen Rider OOO']);
      expect(result.episodeNumber, 1);
      expect(result.releaseTags.resolution, '1080p');
      expect(result.releaseTags.source, 'BDRip');
      expect(result.releaseTags.codec, 'X265');
      expect(result.releaseTags.audio, contains('AC3'));
      expect(result.releaseTags.releaseGroup, 'KRL');
    });

    test('短横线集号不会被标题末尾季度数字抢占', () {
      final result = analyzer.analyze(
        '[LoliHouse] Isekai Nonbiri Nouka 2 - 07 '
        '[WebRip 1080p HEVC-10bit AAC SRTx2].mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.episode);
      expect(result.titleCandidates, <String>['Isekai Nonbiri Nouka 2']);
      expect(result.episodeNumber, 7);
    });

    test('外挂字幕目录属于透明附属资源目录', () {
      expect(analyzer.isTransparentDirectoryName('外挂字幕'), isTrue);
    });

    test('中文剧名紧接两位数字时识别为分集', () {
      final result = analyzer.analyze(
        '迪迦奥特曼03.mp4',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.episode);
      expect(result.titleCandidates, <String>['迪迦奥特曼']);
      expect(result.episodeNumber, 3);
    });

    test('广告和推广入口获得明确角色', () {
      for (final name in <String>[
        '0001更多资源请访问 00t.vip',
        '0002全网搜索资源 qwsou.vip',
        '0000防走失地址.png',
        '更多【神秘入口】.png',
      ]) {
        expect(
          analyzer
              .analyze(
                name,
                isDirectory: !name.toLowerCase().endsWith('.png'),
              )
              .role,
          MediaNodeRole.advertisement,
          reason: name,
        );
      }
    });

    test('电影年份画质和标题数字不会成为分集', () {
      for (final name in <String>[
        '流浪地球2 2023 4K.mkv',
        'interstellar 2014 imax 4K-kc.mkv',
      ]) {
        expect(
          analyzer.analyze(name, isDirectory: false).role,
          isNot(MediaNodeRole.episode),
          reason: name,
        );
      }
    });

    test('电影音轨数量和发布组尾缀不会污染作品名或触发集号', () {
      final result = analyzer.analyze(
        'Annihilation.2018.BluRay.2160p.x265.10bit.HDR.3Audio.-SSDSSE.mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.work);
      expect(result.episodeNumber, isNull);
      expect(result.titleCandidates, <String>['Annihilation']);
    });

    test('有效剪辑版本不会被当成广告或普通重复项', () {
      final result = analyzer.analyze(
        '假面骑士OOO 第47-48集（导演剪辑版）.mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.version);
      expect(result.evidence, contains('director-cut'));
    });

    test('剧场版和 OVA 提供电影内容提示并保留完整作品标题', () {
      final theatrical = analyzer.analyze(
        '中二病也要谈恋爱 剧场版 Take On Me 2160p BluRay H265.mkv',
        isDirectory: false,
      );
      final ova = analyzer.analyze('摇曳露营 OVA.mkv', isDirectory: false);

      expect(theatrical.contentHint, MediaContentHint.movie);
      expect(
        theatrical.titleCandidates,
        contains('中二病也要谈恋爱 剧场版 Take On Me'),
      );
      expect(theatrical.releaseTags.resolution, '2160p');
      expect(ova.contentHint, MediaContentHint.ova);
      expect(ova.titleCandidates, contains('摇曳露营 OVA'));
    });

    test('剧场版发布规格中的位深数字不作为集号', () {
      final result = analyzer.analyze(
        "[KRSUB][Kamen Rider × Kamen Rider OOO & W feat. Skull Movie War "
        "Core Director's Cut][BDrip][1080p][HEVC-10bit][FLAC][CHS].mkv",
        isDirectory: false,
      );

      expect(result.role, isNot(MediaNodeRole.episode),
          reason: result.evidence.toString());
      expect(result.episodeNumber, isNull, reason: result.evidence.toString());
    });

    test('明确季集号优先于特别篇电影提示', () {
      final result = analyzer.analyze(
        '作品 S01E03 特别篇 1080p.mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.episode);
      expect(result.seasonNumber, 1);
      expect(result.episodeNumber, 3);
      expect(result.contentHint, MediaContentHint.special);
    });

    test('语言和字幕规格不改变电影标题身份', () {
      final mandarin = analyzer.analyze(
        '示例电影 2026 2160p 国语 内封简繁.mkv',
        isDirectory: false,
      );
      final japanese = analyzer.analyze(
        '示例电影 2026 1080p 日语 内嵌中字.mkv',
        isDirectory: false,
      );

      expect(mandarin.titleCandidates.first, '示例电影');
      expect(japanese.titleCandidates.first, '示例电影');
      expect(mandarin.releaseTags.audio, contains('国语'));
      expect(japanese.releaseTags.audio, contains('日语'));
    });

    test('合法数字作品标题不会按季度编号删除', () {
      for (final title in <String>['The 100', '1923', '86 -不存在战区-']) {
        final directory = analyzer.analyze(title, isDirectory: true);
        final video = analyzer.analyze('$title.mkv', isDirectory: false);
        expect(directory.role, MediaNodeRole.work, reason: title);
        expect(directory.titleCandidates, contains(title), reason: title);
        expect(video.role, MediaNodeRole.work, reason: '$title.mkv');
        expect(video.titleCandidates, contains(title), reason: '$title.mkv');
      }
    });

    test('发布规格支持 JSON 往返', () {
      const tags = MediaReleaseTags(
        resolution: '4K',
        source: 'Web-DL',
        codec: 'H265',
        dynamicRange: <String>['DV', 'HDR'],
        audio: <String>['DDP 5.1', 'Atmos'],
        releaseGroup: 'Group',
      );

      expect(MediaReleaseTags.fromJson(tags.toJson()), tags);
    });

    test('识别常见网盘资源发布标签', () {
      final result = analyzer.analyze(
        '[Group] 作品 S01E01 2160p REMUX HEVC TrueHD Atmos HLG.mkv',
        isDirectory: false,
      );
      expect(result.releaseTags.resolution, '2160p');
      expect(result.releaseTags.source, 'Remux');
      expect(result.releaseTags.codec, 'HEVC');
      expect(result.releaseTags.audio, contains('TrueHD'));
      expect(result.releaseTags.dynamicRange, contains('HDR'));
    });

    test('扩充流媒体来源、码率、声道和字幕轨道标签', () {
      final result = analyzer.analyze(
        'Cold.War.2016.2160p.HQ.NF.WEB-DL.H265.DTS5.1.SRTx2.mkv',
        isDirectory: false,
      );
      expect(result.releaseTags.bitrate, 'HQ');
      expect(result.releaseTags.source, 'Netflix');
      expect(result.releaseTags.audio, contains('DTS 5.1'));
      expect(result.releaseTags.subtitles, contains('SRTx2'));
    });

    test('字幕版本标签支持 JSON 往返', () {
      const tags = MediaReleaseTags(subtitles: <String>['内封简繁英']);

      expect(MediaReleaseTags.fromJson(tags.toJson()), tags);
    });
  });
}
