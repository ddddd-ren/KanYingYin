import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/diagnostic_log_exporter.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

void main() {
  test('导出脱敏诊断包且保留原日志', () async {
    final tempDir = await Directory.systemTemp.createTemp('diagnostic_logs_');
    final outputDir = await Directory.systemTemp.createTemp('diagnostic_zip_');
    addTearDown(() async {
      await tempDir.delete(recursive: true);
      await outputDir.delete(recursive: true);
    });
    final writer = RotatingLogWriter(directoryProvider: () async => tempDir);
    await writer.write(
      'GET https://drive.example.com/private/video.mkv?token=secret',
    );
    await writer.write(
      'Cookie: session=diagnostic-one; user=diagnostic user; '
      '__puus=diagnostic-three',
    );
    final original = File(
      '${tempDir.path}${Platform.pathSeparator}${RotatingLogWriter.activeFileName}',
    );
    final exporter = DiagnosticLogExporter(
      writer: writer,
      summaryProvider: () async => 'version=1.4.7 token=secret',
    );

    final zip = await exporter.exportTo(outputDir);
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final names = archive.files.map((file) => file.name).toList();
    final content = archive.files
        .where((file) => file.isFile)
        .map((file) => utf8.decode(file.content as List<int>))
        .join('\n');

    expect(names, contains('diagnostic.txt'));
    expect(names, contains(RotatingLogWriter.activeFileName));
    expect(content, contains('https://drive.example.com'));
    expect(content, isNot(contains('/private/video.mkv')));
    expect(content, isNot(contains('secret')));
    expect(content, isNot(contains('diagnostic-one')));
    expect(content, isNot(contains('diagnostic user')));
    expect(content, isNot(contains('diagnostic-three')));
    expect(await original.exists(), isTrue);
  });
}
