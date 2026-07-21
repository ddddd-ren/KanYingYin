import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/logs/logs_page.dart';
import 'package:kanyingyin/utils/log_archive_reader.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

void main() {
  test('读取真实活动日志和轮转日志并可统一清理', () async {
    final root = await Directory.systemTemp.createTemp('log_archive_');
    addTearDown(() => root.delete(recursive: true));
    final writer = RotatingLogWriter(
      directoryProvider: () async => root,
      maxBytes: 12,
      maxFiles: 4,
    );
    await writer.write('第一条较长日志');
    await writer.write('第二条较长日志');
    final reader = LogArchiveReader(writer: writer);

    final content = await reader.readAll();
    expect(content, contains('第一条较长日志'));
    expect(content, contains('第二条较长日志'));

    await reader.clear();
    expect(await writer.listLogFiles(), isEmpty);
  });

  test('没有日志文件时返回空内容', () async {
    final root = await Directory.systemTemp.createTemp('log_archive_empty_');
    addTearDown(() => root.delete(recursive: true));
    final writer = RotatingLogWriter(directoryProvider: () async => root);

    expect(await LogArchiveReader(writer: writer).readAll(), isEmpty);
  });

  test('日志页面使用统一日志读取器', () async {
    final root = await Directory.systemTemp.createTemp('log_page_');
    addTearDown(() => root.delete(recursive: true));
    final writer = RotatingLogWriter(directoryProvider: () async => root);
    final reader = LogArchiveReader(writer: writer);

    final page = LogsPage(reader: reader);

    expect(page.reader, same(reader));
  });
}
