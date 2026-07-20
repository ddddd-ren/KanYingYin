import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';

void main() {
  group('CloudSourcePathScope', () {
    test('使用严格路径边界且空根不匹配任何缓存', () {
      expect(
        CloudSourcePathScope.normalizePath(r'A\\Season 01\\'),
        '/A/Season 01',
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/A'],
          path: '/A/file.mkv',
        ),
        isTrue,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/A'],
          path: '/AB/file.mkv',
        ),
        isFalse,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/'],
          path: '/AB/file.mkv',
        ),
        isTrue,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>[],
          path: '/A/file.mkv',
        ),
        isFalse,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/'],
          path: '',
        ),
        isFalse,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>[''],
          path: '/A/file.mkv',
        ),
        isFalse,
      );
    });

    test('OpenList 忽略根顺序重复项与分隔符差异', () {
      const previous = CloudSource(
        id: 'openlist',
        type: CloudSourceType.openList,
        name: '家庭网盘',
        baseUrl: 'https://drive.example.com',
        rootPaths: <String>['/A/', r'\\B'],
      );
      const current = CloudSource(
        id: 'openlist',
        type: CloudSourceType.openList,
        name: '新名称',
        baseUrl: 'https://drive.example.com',
        rootPaths: <String>['/B', '/A', '/A'],
      );

      expect(
        CloudSourcePathScope.hasRootSelectionChanged(previous, current),
        isFalse,
      );
    });

    test('夸克同路径远程 ID 变化仍触发更新', () {
      const previous = CloudSource(
        id: 'quark',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'old-fid', path: '/影视'),
        ],
      );
      const current = CloudSource(
        id: 'quark',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'new-fid', path: '/影视'),
        ],
      );

      expect(
        CloudSourcePathScope.hasRootSelectionChanged(previous, current),
        isTrue,
      );
    });

    test('新建空根来源不触发更新，有根来源触发更新', () {
      const empty = CloudSource(
        id: 'empty',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>[],
      );
      const configured = CloudSource(
        id: 'configured',
        type: CloudSourceType.openList,
        name: '家庭网盘',
        baseUrl: 'https://drive.example.com',
        rootPaths: <String>['/影视'],
      );

      expect(
        CloudSourcePathScope.hasRootSelectionChanged(null, empty),
        isFalse,
      );
      expect(
        CloudSourcePathScope.hasRootSelectionChanged(null, configured),
        isTrue,
      );
    });
  });
}
