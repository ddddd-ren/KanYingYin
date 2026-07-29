import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/widgets/cloud_directory_picker_page.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

class XunleiDirectoryPickerPage extends StatelessWidget {
  const XunleiDirectoryPickerPage({
    super.key,
    required this.source,
    required this.controller,
    required this.credential,
    this.onCredentialRefreshed,
    this.initialSelection = const <CloudRemoteRef>[],
  });

  final CloudSource source;
  final CloudLibraryController controller;
  final CloudCredential credential;
  final ValueChanged<CloudCredential>? onCredentialRefreshed;
  final List<CloudRemoteRef> initialSelection;

  @override
  Widget build(BuildContext context) =>
      CloudDirectoryPickerPage<List<CloudRemoteRef>>(
        title: '选择迅雷媒体目录',
        root: const CloudRemoteRef(id: '0', path: '/'),
        initialSelection: initialSelection,
        loader: (directory) => controller.browseRemoteDirectories(
          source,
          directory,
          credential: credential,
          onCredentialRefreshed: onCredentialRefreshed,
        ),
        resultBuilder: (selected) => selected,
      );
}
