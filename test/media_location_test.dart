import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';

void main() {
  test('文件路径和文档 URI 使用不同稳定 ID', () {
    final file = MediaLocation.file(r'D:\Media\A.mkv');
    final document = MediaLocation.document(
      uri: 'content://provider/document/video%3A1',
      treeUri: 'content://provider/tree/video',
    );

    expect(file.kind, MediaLocationKind.file);
    expect(document.kind, MediaLocationKind.document);
    expect(file.stableId, isNot(document.stableId));
    expect(MediaLocation.fromJson(document.toJson()), document);
  });

  test('文档位置拒绝非 content URI', () {
    expect(
      () => MediaLocation.document(
        uri: 'file:///video/a.mkv',
        treeUri: 'content://provider/tree/video',
      ),
      throwsFormatException,
    );
  });

  test('Android 索引同时保存媒体、父目录和来源位置', () {
    final source = MediaLocation.document(
      uri: 'content://provider/document/root',
      treeUri: 'content://provider/tree/root',
    );
    final parent = MediaLocation.document(
      uri: 'content://provider/document/season',
      treeUri: source.treeUri!,
    );
    final media = MediaLocation.document(
      uri: 'content://provider/document/video%3A1',
      treeUri: source.treeUri!,
    );
    final item = LocalMediaIndexItem(
      location: media,
      parentLocation: parent,
      sourceLocation: source,
      name: '01.mkv',
      size: 100,
      modified: DateTime(2026),
      seriesName: '剧集',
      indexedAt: DateTime(2026),
    );

    final restored = LocalMediaIndexItem.fromJson(item.toJson());

    expect(restored.location, media);
    expect(restored.parentLocation, parent);
    expect(restored.sourceLocation, source);
    expect(restored.path, media.value);
    expect(restored.id, media.stableId);
  });
}
