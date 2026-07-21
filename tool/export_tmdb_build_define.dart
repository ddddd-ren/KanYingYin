import 'dart:convert';
import 'dart:io';

const _privateBuildKeyEnvironment = 'KANYINGYIN_TMDB_PRIVATE_BUILD_KEY';

Future<void> main(List<String> arguments) async {
  final outputPath = _parseOutputPath(arguments);
  await exportTmdbBuildDefine(
    key: Platform.environment[_privateBuildKeyEnvironment] ?? '',
    outputPath: outputPath,
  );
  stdout.writeln('已生成私密构建参数');
}

Future<void> exportTmdbBuildDefine({
  required String key,
  required String outputPath,
}) async {
  final normalized = key.trim();
  if (normalized.isEmpty) {
    throw StateError('TMDB Key 不能为空');
  }

  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    jsonEncode(<String, String>{
      'KANYINGYIN_TMDB_API_KEY': normalized,
    }),
    encoding: utf8,
    flush: true,
  );
}

String _parseOutputPath(List<String> arguments) {
  String? outputPath;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument != '--output') {
      throw FormatException('不支持的参数：$argument');
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('参数缺少值：$argument');
    }
    final value = arguments[++index].trim();
    if (value.isEmpty) {
      throw FormatException('参数值不能为空：$argument');
    }
    outputPath = value;
  }
  if (outputPath == null) {
    throw const FormatException('用法：--output <临时 JSON 路径>');
  }
  return outputPath;
}
