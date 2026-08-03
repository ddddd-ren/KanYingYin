import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/logs/application/diagnostic_log_share_service.dart';
import 'package:kanyingyin/utils/diagnostic_log_exporter.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

void main() {
  test('在临时目录生成完整诊断包并交给系统分享', () async {
    final logDirectory =
        await Directory.systemTemp.createTemp('diagnostic-share-logs-');
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('diagnostic-share-output-');
    addTearDown(() async {
      await logDirectory.delete(recursive: true);
      await temporaryDirectory.delete(recursive: true);
    });
    final writer = RotatingLogWriter(
      directoryProvider: () async => logDirectory,
    );
    await writer.write('MPV: [ad] truehd decoder failed token=secret');
    final sharePort = _RecordingDiagnosticLogSharePort(
      DiagnosticLogShareOutcome.dismissed,
    );
    final service = DiagnosticLogShareService(
      exporter: DiagnosticLogExporter(
        writer: writer,
        summaryProvider: () async => 'platform=android token=secret',
      ),
      temporaryDirectoryProvider: () async => temporaryDirectory,
      sharePort: sharePort,
    );

    final outcome = await service.share();

    expect(outcome, DiagnosticLogShareOutcome.dismissed);
    expect(sharePort.files, hasLength(1));
    final zip = sharePort.files.single;
    expect(zip.parent.path, temporaryDirectory.path);
    expect(zip.path, endsWith('.zip'));
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final content = archive.files
        .where((file) => file.isFile)
        .map((file) => utf8.decode(file.content as List<int>))
        .join('\n');
    expect(content, contains('truehd decoder failed'));
    expect(content, isNot(contains('secret')));
    expect(
      await File(
        '${logDirectory.path}${Platform.pathSeparator}'
        '${RotatingLogWriter.activeFileName}',
      ).exists(),
      isTrue,
    );
  });
}

class _RecordingDiagnosticLogSharePort implements DiagnosticLogSharePort {
  _RecordingDiagnosticLogSharePort(this.outcome);

  final DiagnosticLogShareOutcome outcome;
  final List<File> files = <File>[];

  @override
  Future<DiagnosticLogShareOutcome> share(File file) async {
    files.add(file);
    return outcome;
  }
}
