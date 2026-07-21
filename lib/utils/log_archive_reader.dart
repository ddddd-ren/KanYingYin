import 'dart:io';

import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

class LogArchiveReader {
  LogArchiveReader({RotatingLogWriter? writer})
      : _writer = writer ?? AppLogOutput.sharedWriter;

  final RotatingLogWriter _writer;

  Future<String> readAll() async {
    await _writer.flush();
    final contents = <String>[];
    for (final file in await _writer.listLogFiles()) {
      try {
        final content = await file.readAsString();
        if (content.isNotEmpty) contents.add(content);
      } on FileSystemException {
        // 日志可能在读取期间轮转，跳过已移动的文件。
      }
    }
    return contents.join('\n');
  }

  Future<void> clear() async {
    await _writer.flush();
    for (final file in await _writer.listLogFiles()) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 文件被并发删除时视为已清理，仍存在则向页面报告失败。
        if (await file.exists()) rethrow;
      }
    }
  }
}
