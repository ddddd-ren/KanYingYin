import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/platform/android/android_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel =
      MethodChannel('com.kanyingyin.player/android.document.test');
  const channel = AndroidPlatformChannel(channel: methodChannel);
  const provider = MethodChannelAndroidDocumentProvider(channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('选择目录转换为文档位置并保留显示名', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'pickDirectory');
      return <String, Object?>{
        'treeUri': 'content://provider/tree/video',
        'documentUri': 'content://provider/document/video',
        'name': '视频',
      };
    });

    final selection = await provider.pickDirectory();

    expect(selection!.name, '视频');
    expect(selection.location.isDocument, isTrue);
    expect(selection.location.treeUri, 'content://provider/tree/video');
  });

  test('枚举目录项保留类型、大小和修改时间', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'listDocumentChildren');
      return <Map<String, Object?>>[
        <String, Object?>{
          'documentUri': 'content://provider/document/folder',
          'name': '文件夹',
          'mimeType': 'vnd.android.document/directory',
          'size': 0,
          'modified': 1000,
        },
        <String, Object?>{
          'documentUri': 'content://provider/document/video%3A1',
          'name': '01.mkv',
          'mimeType': 'video/x-matroska',
          'size': 2048,
          'modified': 2000,
        },
      ];
    });
    final root = _documentLocation();

    final entries = await provider.listChildren(root);

    expect(entries, hasLength(2));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.last.isDirectory, isFalse);
    expect(entries.last.size, 2048);
    expect(entries.last.modified.millisecondsSinceEpoch, 2000);
    expect(entries.last.location.treeUri, root.treeUri);
  });

  test('小文件读取保持字节且平台错误只暴露稳定错误码', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'readSmallDocument') {
        return Uint8List.fromList(<int>[1, 2, 3]);
      }
      throw PlatformException(code: 'PermissionRevoked', message: '私密 URI');
    });
    final root = _documentLocation();

    expect(
      await provider.readSmallFile(root, maxBytes: 16),
      Uint8List.fromList(<int>[1, 2, 3]),
    );
    expect(
      () => provider.canAccess(root),
      throwsA(
        isA<AndroidDocumentException>().having(
          (error) => error.code,
          'code',
          'PermissionRevoked',
        ),
      ),
    );
  });
}

MediaLocation _documentLocation() {
  return MediaLocation.document(
    uri: 'content://provider/document/video',
    treeUri: 'content://provider/tree/video',
  );
}
