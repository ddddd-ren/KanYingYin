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
    await writer.write(
      'provider=xunlei password=password-fixture '
      'refresh_token=refresh-token-fixture '
      'access_token=access-token-fixture '
      'creditkey=credit-key-fixture '
      'captcha_token=captcha-token-fixture '
      'url=https://download.xunlei.com/private-fixture?token=download-secret',
    );
    await writer.write(
      r'{"accessToken":"active-token-value","cookie":"active-cookie-value"} '
      r'media="D:\Users\local-user\Private Media\active.mkv"',
    );
    await File(
      '${tempDir.path}${Platform.pathSeparator}kanyingyin-history.log',
    ).writeAsString(
      r'{refreshToken: history-token-value, '
      r'clientSecret: history-secret-value} '
      r'source="\\media-server\local-user\Private Share\history.mkv"',
    );
    final original = File(
      '${tempDir.path}${Platform.pathSeparator}${RotatingLogWriter.activeFileName}',
    );
    final exporter = DiagnosticLogExporter(
      writer: writer,
      summaryProvider: () async => r'version=1.4.7 apiKey=summary-token-value '
          r'password=summary-secret-value '
          r'profile="/Users/local-user/Private Profile/settings.json"',
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
    expect(names, contains('kanyingyin-history.log'));
    expect(content, contains('https://drive.example.com'));
    expect(content, isNot(contains('/private/video.mkv')));
    expect(content, isNot(contains('secret')));
    expect(content, isNot(contains('diagnostic-one')));
    expect(content, isNot(contains('diagnostic user')));
    expect(content, isNot(contains('diagnostic-three')));
    for (final forbidden in <String>[
      'password-fixture',
      'refresh-token-fixture',
      'access-token-fixture',
      'credit-key-fixture',
      'captcha-token-fixture',
      'https://download.xunlei.com/private-fixture',
      'active-token-value',
      'active-cookie-value',
      'history-token-value',
      'history-secret-value',
      'summary-token-value',
      'summary-secret-value',
      'local-user',
      'Private Media',
      'Private Share',
      'Private Profile',
    ]) {
      expect(content, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(content, contains('[LOCAL_PATH]'));
    expect(await original.exists(), isTrue);
  });
}
