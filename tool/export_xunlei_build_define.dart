import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  await exportXunleiBuildDefine(
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    webClientId: options.webClientId,
    appKey: options.appKey,
    outputPath: options.outputPath,
  );
  stdout.writeln('已生成迅雷构建参数');
}

Future<void> exportXunleiBuildDefine({
  required String clientId,
  required String clientSecret,
  required String webClientId,
  required String appKey,
  required String outputPath,
}) async {
  final normalizedClientId = _requireValue(clientId, 'Client ID');
  final normalizedClientSecret = _requireValue(
    clientSecret,
    'Client Secret',
  );
  final normalizedWebClientId = _requireValue(webClientId, 'Web Client ID');
  final normalizedAppKey = _requireValue(appKey, 'App Key');
  final normalizedOutputPath = _requireValue(outputPath, '输出路径');

  final output = File(normalizedOutputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    jsonEncode(<String, String>{
      'KANYINGYIN_XUNLEI_CLIENT_ID': normalizedClientId,
      'KANYINGYIN_XUNLEI_CLIENT_SECRET': normalizedClientSecret,
      'KANYINGYIN_XUNLEI_WEB_CLIENT_ID': normalizedWebClientId,
      'KANYINGYIN_XUNLEI_APP_KEY': normalizedAppKey,
    }),
    encoding: utf8,
    flush: true,
  );
}

String _requireValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw StateError('$name 不能为空');
  }
  return normalized;
}

_XunleiBuildOptions _parseArguments(List<String> arguments) {
  const supportedArguments = <String>{
    '--client-id',
    '--client-secret',
    '--web-client-id',
    '--app-key',
    '--output',
  };
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!supportedArguments.contains(argument)) {
      throw const FormatException('存在不支持的构建参数');
    }
    if (values.containsKey(argument)) {
      throw FormatException('构建参数重复：$argument');
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('构建参数缺少值：$argument');
    }
    final value = arguments[++index].trim();
    if (value.isEmpty) {
      throw FormatException('构建参数值不能为空：$argument');
    }
    values[argument] = value;
  }

  String requiredArgument(String name) {
    final value = values[name];
    if (value == null) {
      throw FormatException('缺少构建参数：$name');
    }
    return value;
  }

  return _XunleiBuildOptions(
    clientId: requiredArgument('--client-id'),
    clientSecret: requiredArgument('--client-secret'),
    webClientId: requiredArgument('--web-client-id'),
    appKey: requiredArgument('--app-key'),
    outputPath: requiredArgument('--output'),
  );
}

final class _XunleiBuildOptions {
  const _XunleiBuildOptions({
    required this.clientId,
    required this.clientSecret,
    required this.webClientId,
    required this.appKey,
    required this.outputPath,
  });

  final String clientId;
  final String clientSecret;
  final String webClientId;
  final String appKey;
  final String outputPath;
}
