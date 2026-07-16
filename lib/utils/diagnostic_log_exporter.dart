import 'dart:io';

import 'package:archive/archive.dart';
import 'package:kanyingyin/request/config/api_endpoints.dart';
import 'package:kanyingyin/utils/log_sanitizer.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef DiagnosticSummaryProvider = Future<String> Function();

class DiagnosticLogExporter {
  DiagnosticLogExporter({
    RotatingLogWriter? writer,
    LogSanitizer sanitizer = const LogSanitizer(),
    DiagnosticSummaryProvider? summaryProvider,
  })  : _writer = writer ?? AppLogOutput.sharedWriter,
        _sanitizer = sanitizer,
        _summaryProvider = summaryProvider ?? _defaultSummary;

  final RotatingLogWriter _writer;
  final LogSanitizer _sanitizer;
  final DiagnosticSummaryProvider _summaryProvider;

  Future<Directory> getLogDirectory() async {
    await _writer.flush();
    final directory = await _writer.tryGetDirectory();
    if (directory == null) {
      throw const FileSystemException('日志目录不可用');
    }
    return directory;
  }

  Future<void> openLogDirectory() async {
    final directory = await getLogDirectory();
    if (!Platform.isWindows) {
      throw UnsupportedError('当前系统不支持打开日志目录');
    }
    final result = await Process.run('explorer.exe', <String>[directory.path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'explorer.exe',
        <String>[directory.path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }

  Future<File> exportToDownloads() async {
    final directory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return exportTo(directory);
  }

  Future<File> exportTo(Directory outputDirectory) async {
    await _writer.flush();
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'diagnostic.txt',
          _sanitizer.sanitize(await _summaryProvider()),
        ),
      );
    for (final logFile in await _writer.listLogFiles()) {
      try {
        final content = await logFile.readAsString();
        archive.addFile(
          ArchiveFile.string(
            p.basename(logFile.path),
            _sanitizer.sanitize(content),
          ),
        );
      } on FileSystemException {
        // 日志可能在导出期间轮转，跳过已移动的文件。
      }
    }

    final output = File(
      p.join(outputDirectory.path, '看影音-诊断日志-${_timestamp()}.zip'),
    );
    await output.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
    return output;
  }

  static Future<String> _defaultSummary() async {
    var hardwareEnabled = '未知';
    var decoder = '未知';
    try {
      hardwareEnabled = GStorage.setting
          .get(SettingBoxKey.hAenable, defaultValue: true)
          .toString();
      decoder = GStorage.setting
          .get(SettingBoxKey.hardwareDecoder, defaultValue: 'auto-safe')
          .toString();
    } on Object {
      // 存储尚未初始化时仍可导出基础诊断信息。
    }
    return <String>[
      '应用版本: ${ApiEndpoints.version}',
      '系统版本: ${Platform.operatingSystemVersion}',
      '处理器架构: ${Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '未知'}',
      '硬件解码: $hardwareEnabled',
      '解码器: $decoder',
      '生成时间: ${DateTime.now().toIso8601String()}',
    ].join('\n');
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
