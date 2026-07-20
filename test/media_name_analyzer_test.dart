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

    test('有效剪辑版本不会被当成广告或普通重复项', () {
      final result = analyzer.analyze(
        '假面骑士OOO 第47-48集（导演剪辑版）.mkv',
        isDirectory: false,
      );

      expect(result.role, MediaNodeRole.version);
      expect(result.evidence, contains('director-cut'));
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

    test('字幕版本标签支持 JSON 往返', () {
      const tags = MediaReleaseTags(subtitles: <String>['内封简繁英']);

      expect(MediaReleaseTags.fromJson(tags.toJson()), tags);
    });
  });
}
