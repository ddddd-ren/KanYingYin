import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_file_picker_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kanyingyin.player/android');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('TV 导入文件入口转发扩展名和大小并返回缓存路径', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickFile');
      expect(call.arguments, <String, Object>{
        'title': '导入配置',
        'allowedExtensions': const <String>['kyyconfig'],
        'maxBytes': 512 * 1024,
      });
      return <String, Object?>{
        'path': r'C:\cache\import.kyyconfig',
        'name': 'import.kyyconfig',
        'size': 3,
      };
    });

    final path = await pickTvImportFile(
      title: '导入配置',
      allowedExtensions: const <String>['kyyconfig'],
      maxBytes: 512 * 1024,
    );

    expect(path, r'C:\cache\import.kyyconfig');
  });
}
