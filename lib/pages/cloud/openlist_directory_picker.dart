import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/widgets/cloud_directory_picker_page.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

class OpenListDirectoryPickerPage extends StatelessWidget {
  const OpenListDirectoryPickerPage({
    super.key,
    required this.source,
    required this.controller,
    this.credential,
  });

  final CloudSource source;
  final CloudLibraryController controller;
  final CloudCredential? credential;

  @override
  Widget build(BuildContext context) {
    return CloudDirectoryPickerPage<List<String>>(
      title: '选择扫描目录',
      root: const CloudRemoteRef(id: '/', path: '/'),
      initialSelection: source.remoteRoots,
      loader: (directory) => controller.browseRemoteDirectories(
        source,
        directory,
        credential: credential,
      ),
      selectionKeyBuilder: (directory) => directory.path,
      resultBuilder: (selected) =>
          selected.map((directory) => directory.path).toList(growable: false),
    );
  }
}
