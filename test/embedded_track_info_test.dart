import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('内嵌轨道语言识别', () {
    test('识别日语韩语与常见 ISO BCP47 代码', () {
      expect(
        trackLanguageFromMetadata(
          'ja-JP',
          '',
          type: EmbeddedTrackType.subtitle,
        ).label,
        '日语',
      );
      expect(
        trackLanguageFromMetadata(
          'jpn',
          '',
          type: EmbeddedTrackType.subtitle,
        ).label,
        '日语',
      );
      expect(
        trackLanguageFromMetadata(
          'ko',
          '',
          type: EmbeddedTrackType.subtitle,
        ).label,
        '韩语',
      );
      expect(
        trackLanguageFromMetadata(
          'fra',
          '',
          type: EmbeddedTrackType.audio,
        ).label,
        '法语',
      );
      expect(
        trackLanguageFromMetadata(
          '',
          'Japanese Commentary',
          type: EmbeddedTrackType.audio,
        ).label,
        '日语',
      );
    });

    test('识别中文代码和常见配音名称', () {
      expect(
          EmbeddedTrackInfo.fromAudio(const AudioTrack('1', null, 'zh-CN'))
              .kind,
          TrackLanguageKind.mandarin);
      expect(
          EmbeddedTrackInfo.fromAudio(
                  const AudioTrack('2', '粤语 Cantonese', null))
              .kind,
          TrackLanguageKind.cantonese);
      expect(
          EmbeddedTrackInfo.fromAudio(const AudioTrack('3', '台湾国语', null)).kind,
          TrackLanguageKind.taiwaneseMandarin);
    });

    test('识别简体双语繁体字幕和编码', () {
      expect(
          EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('1', '简中', 'chi',
                  codec: 'hdmv_pgs_subtitle'))
              .kind,
          TrackLanguageKind.simplifiedChinese);
      expect(
          EmbeddedTrackInfo.fromSubtitle(
                  const SubtitleTrack('2', '简繁双语', null, codec: 'ass'))
              .kind,
          TrackLanguageKind.bilingualChinese);
      expect(
          EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('3', '繁中', null))
              .kind,
          TrackLanguageKind.traditionalChinese);
      expect(
          EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('1', '简中', 'chi',
                  codec: 'hdmv_pgs_subtitle'))
              .detailLabel,
          contains('PGS'));
    });

    test('未解析轨道只显示类型编号且音轨显示声道', () {
      final unknown =
          EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('7', null, null));
      final audio = EmbeddedTrackInfo.fromAudio(const AudioTrack(
          '4', null, 'eng',
          codec: 'truehd', channelscount: 6));
      expect(unknown.isLanguageResolved, isFalse);
      expect(unknown.primaryLabel, '字幕轨道 7');
      expect('${unknown.primaryLabel} ${unknown.detailLabel}',
          isNot(contains('未知语种')));
      expect(audio.primaryLabel, '英语 / English');
      expect(audio.detailLabel, contains('TrueHD'));
      expect(audio.detailLabel, contains('5.1'));
    });
  });

  test('音轨优先级为国语粤语台配默认轨第一条', () {
    final tracks = [
      EmbeddedTrackInfo.fromAudio(const AudioTrack('1', 'English', 'eng')),
      EmbeddedTrackInfo.fromAudio(const AudioTrack('2', '台配', null)),
      EmbeddedTrackInfo.fromAudio(const AudioTrack('3', '粤语', null)),
      EmbeddedTrackInfo.fromAudio(const AudioTrack('4', '国语', null)),
    ];
    expect(selectPreferredAudioTrack(tracks, defaultTrackId: '1')?.id, '4');
  });

  test('字幕优先级为简体简繁繁体且无中文字幕时关闭', () {
    final tracks = [
      EmbeddedTrackInfo.fromSubtitle(
          const SubtitleTrack('1', 'English', 'eng')),
      EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('2', '繁中', null)),
      EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('3', '简繁', null)),
      EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('4', '简中', null)),
    ];
    expect(selectPreferredSubtitleTrack(tracks, defaultTrackId: '1')?.id, '4');
    expect(selectPreferredSubtitleTrack(tracks.take(1).toList()), isNull);
  });

  test('没有中文字幕时仍选择文件标记的默认字幕', () {
    final tracks = [
      EmbeddedTrackInfo.fromSubtitle(
        const SubtitleTrack('1', 'English', 'eng'),
      ),
    ];
    expect(selectPreferredSubtitleTrack(tracks, defaultTrackId: '1')?.id, '1');
  });
}
