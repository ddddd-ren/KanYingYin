import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/services/android_media_entry_provider.dart';
import 'package:kanyingyin/services/file_system_media_entry_provider.dart';

void main() {
  test('文件系统 provider 只枚举当前层并保留文件属性', () async {
    final directory = await Directory.systemTemp.createTemp('media-entry-');
    addTearDown(() => directory.delete(recursive: true));
    final child = await File('${directory.path}${Platform.pathSeparator}01.mkv')
        .writeAsBytes(<int>[1, 2, 3]);
    await Directory('${directory.path}${Platform.pathSeparator}Season')
        .create();
    const provider = FileSystemMediaEntryProvider();

    final entries = await provider.listChildren(
      MediaLocation.file(directory.path),
    );

    expect(entries, hasLength(2));
    expect(entries.any((entry) => entry.isDirectory), isTrue);
    expect(
      entries.singleWhere((entry) => entry.name == '01.mkv').size,
      await child.length(),
    );
  });

  test('Android provider 适配文档项且不改写 content URI', () async {
    final documents = _FakeDocuments();
    final provider = AndroidMediaEntryProvider(documents);
    final root = MediaLocation.document(
      uri: 'content://provider/document/root',
      treeUri: 'content://provider/tree/root',
    );

    final entries = await provider.listChildren(root);

    expect(provider.supports(root), isTrue);
    expect(entries.single.location.value, 'content://provider/document/Video');
    expect(entries.single.name, '01.mkv');
  });
}

class _FakeDocuments implements AndroidDocumentProvider {
  @override
  Future<bool> canAccess(MediaLocation location) async => true;

  @override
  Future<List<AndroidDocumentEntry>> listChildren(
    MediaLocation parent,
  ) async =>
      <AndroidDocumentEntry>[
        AndroidDocumentEntry(
          location: MediaLocation.document(
            uri: 'content://provider/document/Video',
            treeUri: parent.treeUri!,
          ),
          name: '01.mkv',
          isDirectory: false,
          size: 1024,
          modified: DateTime(2026),
          mimeType: 'video/x-matroska',
        ),
      ];

  @override
  Future<({MediaLocation location, String name})?> pickDirectory() async =>
      null;

  @override
  Future<Uint8List> readSmallFile(
    MediaLocation location, {
    required int maxBytes,
  }) async =>
      Uint8List(0);
}
