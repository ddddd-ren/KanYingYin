import 'dart:io';

import 'package:kanyingyin/utils/diagnostic_log_exporter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum DiagnosticLogShareOutcome { shared, dismissed }

typedef DiagnosticTemporaryDirectoryProvider = Future<Directory> Function();

abstract interface class DiagnosticLogSharePort {
  Future<DiagnosticLogShareOutcome> share(File file);
}

class DiagnosticLogShareService {
  DiagnosticLogShareService({
    DiagnosticLogExporter? exporter,
    DiagnosticTemporaryDirectoryProvider? temporaryDirectoryProvider,
    DiagnosticLogSharePort? sharePort,
  })  : _exporter = exporter ?? DiagnosticLogExporter(),
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _sharePort = sharePort ?? const SharePlusDiagnosticLogSharePort();

  final DiagnosticLogExporter _exporter;
  final DiagnosticTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final DiagnosticLogSharePort _sharePort;

  Future<DiagnosticLogShareOutcome> share() async {
    final directory = await _temporaryDirectoryProvider();
    final file = await _exporter.exportTo(directory);
    return _sharePort.share(file);
  }
}

class SharePlusDiagnosticLogSharePort implements DiagnosticLogSharePort {
  const SharePlusDiagnosticLogSharePort();

  @override
  Future<DiagnosticLogShareOutcome> share(File file) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        title: '分享看影音诊断日志',
        subject: '看影音诊断日志',
        text: '看影音诊断日志（已脱敏）',
        files: <XFile>[
          XFile(file.path, mimeType: 'application/zip'),
        ],
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? DiagnosticLogShareOutcome.dismissed
        : DiagnosticLogShareOutcome.shared;
  }
}
