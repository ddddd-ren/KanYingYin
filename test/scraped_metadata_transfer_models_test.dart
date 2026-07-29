import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';

void main() {
  test('迁移数据使用版本 1 往返且不序列化旧设备图片绝对路径', () {
    final payload = ScrapedMetadataPayload(
      formatVersion: 1,
      exportedAt: DateTime.utc(2026, 7, 30),
      appVersion: '2.1.93',
      localSources: <PortableLocalSource>[
        PortableLocalSource(
          exportId: 'local-source',
          name: '本地影视',
          originalRoot: r'D:\影视',
          records: <PortableLocalRecord>[
            PortableLocalRecord(
              relativePath: r'三体\S01E01.mkv',
              size: 1024,
              tmdb: <String, Object?>{'id': 42, 'title': '三体'},
              scrapeStatus: 'matched',
              tmdbMatchOrigin: 'manual',
              tmdbRuleVersion: 3,
              titleLocked: true,
              posterLocked: true,
              overviewLocked: false,
              manualOverride: true,
              posterImage: 'images/abc.jpg',
              backdropImage: 'images/def.jpg',
              seasonImages: const <int, String>{1: 'images/season.jpg'},
            ),
          ],
        ),
      ],
      cloudSources: <PortableCloudSource>[
        const PortableCloudSource(
          exportId: 'cloud-source',
          type: CloudSourceType.quark,
          name: '夸克',
          sanitizedBaseUrl: '',
          roots: <PortableCloudRoot>[
            PortableCloudRoot(id: 'root', path: '/影视'),
          ],
          resourceRecords: <PortableCloudRecord>[],
          workRecords: <PortableCloudRecord>[],
          seriesRules: <PortableCloudRecord>[],
        ),
      ],
    );

    final restored = ScrapedMetadataPayload.fromJson(payload.toJson());
    final encoded = jsonEncode(restored.toJson());

    expect(restored.formatVersion, scrapedMetadataFormatVersion);
    expect(restored.localSources.single.records.single.tmdb['title'], '三体');
    expect(restored.cloudSources.single.type, CloudSourceType.quark);
    expect(encoded, isNot(contains(r'C:\cache')));
    expect(
      restored.localSources.single.records.single.posterImage,
      'images/abc.jpg',
    );
  });

  test('迁移数据拒绝缺少格式版本', () {
    expect(
      () => ScrapedMetadataPayload.fromJson(<String, Object?>{
        'exportedAt': '2026-07-30T00:00:00.000Z',
        'appVersion': '2.1.93',
        'localSources': const <Object?>[],
        'cloudSources': const <Object?>[],
      }),
      throwsFormatException,
    );
  });

  test('本地迁移记录拒绝空相对路径和负数大小', () {
    expect(
      () => PortableLocalRecord.fromJson(<String, Object?>{
        'relativePath': '',
        'size': -1,
        'tmdb': <String, Object?>{'id': 42, 'title': '三体'},
        'scrapeStatus': 'matched',
        'tmdbMatchOrigin': 'manual',
        'tmdbRuleVersion': 3,
      }),
      throwsFormatException,
    );
  });

  test('迁移数据拒绝超过记录上限', () {
    final records = List<Object?>.filled(
      maxTransferRecords + 1,
      <String, Object?>{
        'relativePath': 'video.mkv',
        'size': 1,
        'tmdb': <String, Object?>{'id': 1, 'title': '作品'},
        'scrapeStatus': 'matched',
        'tmdbMatchOrigin': 'manual',
        'tmdbRuleVersion': 1,
      },
    );
    expect(
      () => ScrapedMetadataPayload.fromJson(<String, Object?>{
        'formatVersion': 1,
        'exportedAt': '2026-07-30T00:00:00.000Z',
        'appVersion': '2.1.93',
        'localSources': <Object?>[
          <String, Object?>{
            'exportId': 'source',
            'name': '来源',
            'originalRoot': r'D:\影视',
            'records': records,
          },
        ],
        'cloudSources': const <Object?>[],
      }),
      throwsFormatException,
    );
  });
}
