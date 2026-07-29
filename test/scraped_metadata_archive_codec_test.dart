import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('kyymeta-codec-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('迁移包写入固定结构并校验后往返', () async {
    final image = File('${temporary.path}${Platform.pathSeparator}海报.jpg');
    await image.writeAsBytes(<int>[1, 2, 3, 4]);
    final output = File('${temporary.path}${Platform.pathSeparator}资料.kyymeta');
    final codec = ScrapedMetadataArchiveCodec(
      temporaryDirectoryProvider: () async => temporary,
    );

    await codec.write(
      output: output,
      payload: _payload(),
      images: <String, File>{'images/abc.jpg': image},
    );

    final archive = ZipDecoder().decodeBytes(await output.readAsBytes());
    expect(
      archive.files.where((file) => file.isFile).map((file) => file.name),
      containsAll(<String>[
        'manifest.json',
        'local.json',
        'cloud.json',
        'images/abc.jpg',
      ]),
    );

    final decoded = await codec.read(output);
    addTearDown(decoded.dispose);
    expect(
      decoded.payload.localSources.single.records.single.tmdb['title'],
      '三体',
    );
    expect(await decoded.imageFiles['images/abc.jpg']!.readAsBytes(), <int>[
      1,
      2,
      3,
      4,
    ]);
  });

  test('迁移包拒绝路径穿越和绝对路径', () async {
    final codec = ScrapedMetadataArchiveCodec(
      temporaryDirectoryProvider: () async => temporary,
    );
    for (final name in <String>[
      '../outside.jpg',
      '/absolute.jpg',
      r'C:\absolute.jpg',
      'images/../outside.jpg',
    ]) {
      final archive = Archive()
        ..addFile(ArchiveFile.string(name, 'bad'))
        ..addFile(ArchiveFile.string('manifest.json', '{}'));
      final input = File(
        '${temporary.path}${Platform.pathSeparator}'
        '${name.hashCode}.kyymeta',
      );
      await input.writeAsBytes(ZipEncoder().encodeBytes(archive));

      await expectLater(codec.read(input), throwsFormatException);
    }
  });

  test('迁移包拒绝未知格式版本和哈希不一致', () async {
    final input = File(
      '${temporary.path}${Platform.pathSeparator}tampered.kyymeta',
    );
    final local = utf8.encode(jsonEncode(<String, Object?>{
      'localSources':
          _payload().localSources.map((source) => source.toJson()).toList(),
    }));
    final cloud = utf8.encode('{"cloudSources":[]}');
    final manifest = <String, Object?>{
      'format': scrapedMetadataFormat,
      'formatVersion': 2,
      'appVersion': '2.1.93',
      'exportedAt': '2026-07-30T00:00:00.000Z',
      'localRecordCount': 1,
      'cloudRecordCount': 0,
      'files': <Object?>[
        <String, Object?>{
          'path': 'local.json',
          'length': local.length,
          'sha256': 'not-the-real-hash',
        },
        <String, Object?>{
          'path': 'cloud.json',
          'length': cloud.length,
          'sha256': 'not-the-real-hash',
        },
      ],
    };
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..addFile(ArchiveFile.bytes('local.json', local))
      ..addFile(ArchiveFile.bytes('cloud.json', cloud));
    await input.writeAsBytes(ZipEncoder().encodeBytes(archive));

    final codec = ScrapedMetadataArchiveCodec(
      temporaryDirectoryProvider: () async => temporary,
    );
    await expectLater(codec.read(input), throwsFormatException);
  });
}

ScrapedMetadataPayload _payload() => ScrapedMetadataPayload(
      formatVersion: scrapedMetadataFormatVersion,
      exportedAt: DateTime.utc(2026, 7, 30),
      appVersion: '2.1.93',
      localSources: <PortableLocalSource>[
        PortableLocalSource(
          exportId: 'local',
          name: '影视',
          originalRoot: r'D:\影视',
          records: <PortableLocalRecord>[
            PortableLocalRecord(
              relativePath: r'三体\S01E01.mkv',
              size: 1024,
              tmdb: <String, Object?>{'id': 42, 'title': '三体'},
              scrapeStatus: 'matched',
              tmdbMatchOrigin: 'manual',
              tmdbRuleVersion: 1,
              posterImage: 'images/abc.jpg',
            ),
          ],
        ),
      ],
      cloudSources: const <PortableCloudSource>[],
    );
