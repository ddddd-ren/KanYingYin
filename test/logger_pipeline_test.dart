import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';
import 'package:logger/logger.dart';

void main() {
  test('所有日志等级默认写入脱敏文件管线', () async {
    final tempDir = await Directory.systemTemp.createTemp('logger_pipeline_');
    addTearDown(() => tempDir.delete(recursive: true));
    final writer = RotatingLogWriter(
      directoryProvider: () async => tempDir,
      maxBytes: 1024 * 1024,
    );
    final output = AppLogOutput(writer: writer);

    output.output(OutputEvent(
      LogEvent(Level.info, 'ignored'),
      [
        '\x1B[32mGET https://drive.example.com/private/a.mkv?token=secret\x1B[0m'
      ],
    ));
    await output.flush();

    final log = File('${tempDir.path}${Platform.pathSeparator}kanyingyin.log');
    final content = await log.readAsString();
    expect(content, contains('GET https://drive.example.com'));
    expect(content, isNot(contains('/private/a.mkv')));
    expect(content, isNot(contains('secret')));
    expect(content, isNot(contains('\x1B')));
  });

  test('应用启动注册 Flutter 和平台未捕获异常日志', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('FlutterError.onError'));
    expect(source, contains('PlatformDispatcher.instance.onError'));
    expect(source, contains('runZonedGuarded'));
  });

  test('播放器日志绕过同步控制台输出并写入脱敏文件', () {
    final source = File('lib/utils/logger.dart').readAsStringSync();

    expect(source, contains('void writePlayerLog(String message)'));
    expect(source, contains('AppLogOutput.sharedWriter.write'));
    expect(source, contains('LogSanitizer().sanitize(message)'));
  });
}
