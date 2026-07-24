import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_directory_scope_tree.dart';

void main() {
  group('CloudDirectoryScopeTree', () {
    test('多根目录只暴露配置根且按路径段过滤子树', () {
      final tree = CloudDirectoryScopeTree.build(
        rootPaths: const <String>['/影视', '/动漫/季度'],
        mediaPaths: const <String>[
          '/影视/电影/正片.mkv',
          '/影视剧/不应命中.mkv',
          '/动漫/季度/作品/S01E01.mkv',
        ],
      );

      expect(
        tree.childrenOf(null).map((item) => item.path),
        <String>['/动漫/季度', '/影视'],
      );
      expect(
        tree.childrenOf('/影视').map((item) => item.path),
        <String>['/影视/电影'],
      );
      expect(tree.contains('/影视/电影/正片.mkv', '/影视'), isTrue);
      expect(tree.contains('/影视剧/不应命中.mkv', '/影视'), isFalse);
      expect(tree.parentOf('/影视/电影'), '/影视');
      expect(tree.parentOf('/影视'), isNull);
    });

    test('根目录范围下拉直接子目录且规范化反斜杠', () {
      final tree = CloudDirectoryScopeTree.build(
        rootPaths: const <String>['/'],
        mediaPaths: const <String>[
          r'\影视\电影\A.mkv',
          '/影视/剧集/B.mkv',
          '/动漫/C.mkv',
        ],
      );

      expect(
        tree.childrenOf('/').map((item) => item.path),
        <String>['/动漫', '/影视'],
      );
      expect(
        tree.childrenOf('/影视').map((item) => item.path),
        unorderedEquals(<String>['/影视/电影', '/影视/剧集']),
      );
      expect(tree.hasDirectory('/影视/电影/'), isTrue);
    });

    test('空索引仍保留已配置媒体根目录', () {
      final tree = CloudDirectoryScopeTree.build(
        rootPaths: const <String>['/空目录'],
        mediaPaths: const <String>[],
      );

      expect(tree.childrenOf(null).single.path, '/空目录');
      expect(tree.childrenOf('/空目录'), isEmpty);
      expect(tree.contains('/空目录/影片.mkv', null), isTrue);
    });
  });
}
