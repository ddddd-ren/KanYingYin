import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final hiveDirectory = Directory(options.hiveDirectory);
  if (!await hiveDirectory.exists()) {
    throw FileSystemException('看影音设置目录不存在', hiveDirectory.path);
  }

  Box<Object?>? setting;
  try {
    Hive.init(hiveDirectory.path);
    setting = await Hive.openBox<Object?>('setting');
    final value = setting.get('tmdbApiKey');
    final tmdbApiKey = value is String ? value.trim() : '';
    if (tmdbApiKey.isEmpty) {
      throw StateError('当前看影音设置中没有可用于私人构建的 TMDB Key');
    }

    final output = File(options.outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      jsonEncode(<String, String>{
        'KANYINGYIN_TMDB_API_KEY': tmdbApiKey,
      }),
      encoding: utf8,
      flush: true,
    );
    stdout.writeln('已生成私密构建参数');
  } finally {
    await setting?.close();
    await Hive.close();
  }
}

_ExportOptions _parseArguments(List<String> arguments) {
  String? hiveDirectory;
  String? outputPath;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument != '--hive-directory' && argument != '--output') {
      throw FormatException('不支持的参数：$argument');
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('参数缺少值：$argument');
    }
    final value = arguments[++index].trim();
    if (value.isEmpty) throw FormatException('参数值不能为空：$argument');
    if (argument == '--hive-directory') {
      hiveDirectory = value;
    } else {
      outputPath = value;
    }
  }
  if (hiveDirectory == null || outputPath == null) {
    throw const FormatException(
      '用法：--hive-directory <设置目录> --output <临时 JSON 路径>',
    );
  }
  return _ExportOptions(
    hiveDirectory: hiveDirectory,
    outputPath: outputPath,
  );
}

class _ExportOptions {
  const _ExportOptions({
    required this.hiveDirectory,
    required this.outputPath,
  });

  final String hiveDirectory;
  final String outputPath;
}
