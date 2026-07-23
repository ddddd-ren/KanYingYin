import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_transfer_target_policy.dart';

void main() {
  const source = CloudSource(
    id: 'quark-a',
    type: CloudSourceType.quark,
    name: '夸克网盘',
    baseUrl: 'https://pan.quark.cn',
    rootPaths: <String>['/影视'],
    rootRefs: <CloudRemoteRef>[
      CloudRemoteRef(id: 'movies-id', path: '/影视'),
    ],
  );

  test('未覆盖的转存目录会成为默认目录和媒体根目录', () {
    const target = CloudRemoteRef(id: 'incoming-id', path: '/接收');

    final updated = QuarkTransferTargetPolicy.apply(source, target);

    expect(updated.defaultTransferDirectory, target);
    expect(updated.remoteRoots, contains(target));
    expect(updated.rootPaths, <String>['/影视', '/接收']);
  });

  test('已有上级媒体根目录时不重复追加转存目录', () {
    const target = CloudRemoteRef(id: 'season-id', path: '/影视/电视剧');

    final updated = QuarkTransferTargetPolicy.apply(source, target);

    expect(updated.defaultTransferDirectory, target);
    expect(updated.remoteRoots, source.remoteRoots);
  });

  test('同路径远程 ID 变化时替换旧根引用', () {
    const target = CloudRemoteRef(id: 'new-movies-id', path: '/影视');

    final updated = QuarkTransferTargetPolicy.apply(source, target);

    expect(updated.remoteRoots, <CloudRemoteRef>[target]);
  });
}
