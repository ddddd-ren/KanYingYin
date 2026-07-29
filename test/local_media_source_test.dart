import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/media_location.dart';

void main() {
  test('旧路径来源迁移为文件位置并保持旧 path 字段', () {
    final source = LocalMediaSource.fromJson({
      'id': r'd:\media',
      'path': r'D:\Media',
      'name': '媒体',
    });

    expect(source.location.isFile, isTrue);
    expect(source.path, r'D:\Media');
    expect(source.id, source.location.stableId);
    expect(source.toJson()['path'], source.path);
  });

  test('Android 文档来源往返序列化不改变 URI', () {
    final source = LocalMediaSource.fromLocation(
      MediaLocation.document(
        uri: 'content://provider/document/video%3A1',
        treeUri: 'content://provider/tree/video',
      ),
      displayName: '视频',
    );

    final restored = LocalMediaSource.fromJson(source.toJson());

    expect(restored.location, source.location);
    expect(restored.name, '视频');
  });
}
