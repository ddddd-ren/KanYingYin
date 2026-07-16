import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef LogDirectoryProvider = Future<Directory> Function();

class RotatingLogWriter {
  RotatingLogWriter({
    LogDirectoryProvider? directoryProvider,
    this.maxBytes = 10 * 1024 * 1024,
    this.maxFiles = 10,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectoryProvider {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    if (maxFiles <= 0) throw ArgumentError.value(maxFiles, 'maxFiles');
  }

  static const String activeFileName = 'kanyingyin.log';

  final LogDirectoryProvider _directoryProvider;
  final int maxBytes;
  final int maxFiles;

  Future<void> _tail = Future<void>.value();
  int _rotationSequence = 0;

  Future<void> write(String line) {
    _tail = _tail.then((_) => _writeSafely(line));
    return _tail;
  }

  Future<void> flush() => _tail;

  Future<Directory?> tryGetDirectory() async {
    try {
      final directory = await _directoryProvider();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } catch (error) {
      stderr.writeln('日志目录不可用: $error');
      return null;
    }
  }

  Future<List<File>> listLogFiles() async {
    await flush();
    final directory = await tryGetDirectory();
    if (directory == null) return const <File>[];
    try {
      final files = await directory
          .list()
          .where((entity) => entity is File && _isLogFile(entity.path))
          .cast<File>()
          .toList();
      files.sort((left, right) {
        if (p.basename(left.path) == activeFileName) return -1;
        if (p.basename(right.path) == activeFileName) return 1;
        return right.lastModifiedSync().compareTo(left.lastModifiedSync());
      });
      return files;
    } catch (error) {
      stderr.writeln('读取日志列表失败: $error');
      return const <File>[];
    }
  }

  Future<void> _writeSafely(String line) async {
    try {
      final directory = await tryGetDirectory();
      if (directory == null) return;
      final file = File(p.join(directory.path, activeFileName));
      final text = line.endsWith('\n') ? line : '$line\n';
      final byteLength = utf8.encode(text).length;
      if (await file.exists() &&
          await file.length() > 0 &&
          await file.length() + byteLength > maxBytes) {
        await _rotate(directory, file);
      }
      await file.writeAsString(
        text,
        mode: FileMode.writeOnlyAppend,
        encoding: utf8,
        flush: false,
      );
    } catch (error) {
      stderr.writeln('写入日志失败: $error');
    }
  }

  Future<void> _rotate(Directory directory, File activeFile) async {
    final now = DateTime.now().toUtc();
    final timestamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final sequence = (_rotationSequence++).toString().padLeft(4, '0');
    final history = File(
      p.join(directory.path, 'kanyingyin-$timestamp-$sequence.log'),
    );
    await activeFile.rename(history.path);
    await _deleteExpiredFiles(directory);
  }

  Future<void> _deleteExpiredFiles(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) => entity is File && _isLogFile(entity.path))
        .cast<File>()
        .toList();
    if (files.length < maxFiles) return;
    files.sort(
      (left, right) => left.lastModifiedSync().compareTo(
            right.lastModifiedSync(),
          ),
    );
    final removeCount = files.length - maxFiles + 1;
    for (final file in files.take(removeCount)) {
      try {
        await file.delete();
      } catch (error) {
        stderr.writeln('删除旧日志失败: ${file.path}: $error');
      }
    }
  }

  bool _isLogFile(String path) {
    final name = p.basename(path);
    return name == activeFileName ||
        (name.startsWith('kanyingyin-') && name.endsWith('.log'));
  }

  static Future<Directory> _defaultDirectoryProvider() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'logs'));
  }
}
