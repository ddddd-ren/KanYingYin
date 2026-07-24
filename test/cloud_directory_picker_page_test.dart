import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_directory_address_resolver.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/pages/cloud/widgets/cloud_directory_picker_page.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('远程地址从根目录逐级解析真实目录 ID', () async {
    final listed = <String>[];
    final resolver = CloudDirectoryAddressResolver(
      loader: (directory) async {
        listed.add(directory.id);
        if (directory.path == '/') {
          return const <CloudFileEntry>[
            CloudFileEntry(
              id: 'fid-tv',
              remotePath: '/影视',
              name: '影视',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
          ];
        }
        return const <CloudFileEntry>[
          CloudFileEntry(
            id: 'fid-show',
            remotePath: '/影视/剧集',
            name: '剧集',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ];
      },
    );

    final result = await resolver.resolve(
      root: const CloudRemoteRef(id: '0', path: '/'),
      targetPath: '/影视/剧集',
    );

    expect(
        result.current, const CloudRemoteRef(id: 'fid-show', path: '/影视/剧集'));
    expect(
      result.ancestry,
      const <CloudRemoteRef>[
        CloudRemoteRef(id: '0', path: '/'),
        CloudRemoteRef(id: 'fid-tv', path: '/影视'),
      ],
    );
    expect(listed, <String>['0', 'fid-tv']);
  });

  testWidgets('统一网盘选择页支持地址栏、进入目录和多选当前目录', (tester) async {
    Future<List<CloudFileEntry>> loader(CloudRemoteRef directory) async {
      if (directory.path == '/') {
        return const <CloudFileEntry>[
          CloudFileEntry(
            id: 'tv',
            remotePath: '/影视',
            name: '影视',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ];
      }
      return const <CloudFileEntry>[];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CloudDirectoryPickerPage<List<CloudRemoteRef>>(
          title: '选择网盘目录',
          root: const CloudRemoteRef(id: '0', path: '/'),
          initialSelection: const <CloudRemoteRef>[],
          loader: loader,
          resultBuilder: (selected) => selected,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cloud-directory-address')),
      findsOneWidget,
    );
    expect(find.text('影视'), findsOneWidget);
    await tester.tap(find.text('影视'));
    await tester.pumpAndSettle();
    expect(find.text('/影视'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('select-current-directory')),
    );
    await tester.pump();
    expect(find.text('已选 1 个'), findsOneWidget);
    expect(find.text('当前目录没有子文件夹'), findsOneWidget);
    expect(find.byTooltip('上级目录'), findsOneWidget);
  });

  testWidgets('地址解析失败保留当前列表和已选目录', (tester) async {
    const folder = CloudFileEntry(
      id: 'tv',
      remotePath: '/影视',
      name: '影视',
      size: 0,
      modifiedAt: null,
      isDirectory: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudDirectoryPickerPage<List<CloudRemoteRef>>(
          title: '选择网盘目录',
          root: const CloudRemoteRef(id: '0', path: '/'),
          initialSelection: const <CloudRemoteRef>[
            CloudRemoteRef(id: 'tv', path: '/影视'),
          ],
          loader: (_) async => const <CloudFileEntry>[folder],
          resultBuilder: (selected) => selected,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('cloud-directory-address')),
      '/不存在',
    );
    await tester.tap(find.widgetWithText(FilledButton, '跳转'));
    await tester.pumpAndSettle();

    expect(find.text('目录不存在或无法访问'), findsOneWidget);
    expect(find.text('影视'), findsOneWidget);
    expect(find.text('已选 1 个'), findsOneWidget);
  });
}
