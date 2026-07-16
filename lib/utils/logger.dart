// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/utils/log_sanitizer.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

const Symbol _forceLogKey = #_forceLog;

class AppLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

class AppLogPrinter extends PrettyPrinter {
  AppLogPrinter()
      : super(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 120,
          colors: true,
          // Disable emojis for better compatibility
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        );

  @override
  List<String> log(LogEvent event) {
    // For trace, debug, info - never show stack trace
    if (event.level == Level.trace ||
        event.level == Level.debug ||
        event.level == Level.info) {
      final messageStr = stringifyMessage(event.message);
      final time = getTime(event.time);
      final prefix = _getPrefix(event.level);
      final levelName = _getLevelName(event.level);

      return [
        '$prefix $time $levelName $messageStr',
      ];
    }

    // For warning, error, fatal - use default behavior which shows stack if provided
    return super.log(event);
  }

  /// Colored prefix for log level
  String _getPrefix(Level level) {
    if (!colors) return _getLevelTag(level);

    const reset = '\x1B[0m';
    String colorCode;

    switch (level) {
      case Level.trace:
        colorCode = '\x1B[90m'; // Bright Black
      case Level.debug:
        colorCode = '\x1B[36m'; // Cyan
      case Level.info:
        colorCode = '\x1B[32m'; // Green
      case Level.warning:
        colorCode = '\x1B[33m'; // Yellow
      case Level.error:
        colorCode = '\x1B[31m'; // Red
      case Level.fatal:
        colorCode = '\x1B[35m'; // Magenta
      default:
        colorCode = '';
    }

    return '$colorCode${_getLevelTag(level)}$reset';
  }

  /// Tag symbol for log level
  String _getLevelTag(Level level) {
    switch (level) {
      case Level.trace:
        return '[·]';
      case Level.debug:
        return '[*]';
      case Level.info:
        return '[i]';
      case Level.warning:
        return '[!]';
      case Level.error:
        return '[×]';
      case Level.fatal:
        return '[‼]';
      default:
        return '[-]';
    }
  }

  String _getLevelName(Level level) {
    return level.name.toUpperCase().padRight(7);
  }
}

class AppLogOutput extends LogOutput {
  AppLogOutput({
    RotatingLogWriter? writer,
    LogSanitizer sanitizer = const LogSanitizer(),
  })  : _writer = writer ?? sharedWriter,
        _sanitizer = sanitizer;

  static final RotatingLogWriter sharedWriter = RotatingLogWriter();

  final RotatingLogWriter _writer;
  final LogSanitizer _sanitizer;

  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      print(line);
    }

    _writeToFile(event);
  }

  void _writeToFile(OutputEvent event) {
    final buffer = StringBuffer()
      ..writeln(
        '[${DateTime.now().toIso8601String()}] ${event.level.name.toUpperCase()}',
      );
    for (final line in event.lines) {
      buffer.writeln(_sanitizer.sanitize(_removeAnsiCodes(line)));
    }
    unawaited(_writer.write(buffer.toString().trimRight()));
  }

  Future<void> flush() => _writer.flush();

  /// Remove ANSI escape codes from string to ensure clean log files
  String _removeAnsiCodes(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }
}

class AppLogger {
  AppLogger._internal() {
    _logger = Logger(
      filter: AppLogFilter(),
      printer: AppLogPrinter(),
      output: AppLogOutput(),
    );
  }

  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() {
    return _instance;
  }

  late final Logger _logger;
  void _log(void Function() logFn, bool forceLog) {
    if (forceLog) {
      runZoned(logFn, zoneValues: {_forceLogKey: true});
    } else {
      logFn();
    }
  }

  /// Trace log - lowest level, very detailed information
  void t(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.t(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// Debug log - detailed information for debugging
  void d(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.d(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// Info log - informational messages
  void i(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.i(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// Warning log - potentially harmful situations
  void w(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.w(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// Error log - error events that might still allow the app to continue
  void e(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.e(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// Fatal log - very severe error events that will presumably lead the app to abort
  void f(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.f(message, error: error, stackTrace: stackTrace),
        forceLog);
  }
}

void writePlayerLog(String message) {
  final sanitized = const LogSanitizer().sanitize(message);
  unawaited(
    AppLogOutput.sharedWriter.write(
      '[${DateTime.now().toIso8601String()}] PLAYER\n$sanitized',
    ),
  );
}

Future<File> getLogsPath() async {
  await AppLogOutput.sharedWriter.flush();
  final directory = await AppLogOutput.sharedWriter.tryGetDirectory();
  if (directory == null) {
    throw const FileSystemException('日志目录不可用');
  }
  final file = File(p.join(directory.path, RotatingLogWriter.activeFileName));
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
  return file;
}

Future<bool> clearLogs() async {
  try {
    await AppLogOutput.sharedWriter.flush();
    final files = await AppLogOutput.sharedWriter.listLogFiles();
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
    return true;
  } catch (e) {
    print('Error clearing file: $e');
    return false;
  }
}
