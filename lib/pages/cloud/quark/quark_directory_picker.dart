import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/widgets/cloud_directory_picker_page.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

class QuarkDirectoryPickerPage extends StatelessWidget {
  const QuarkDirectoryPickerPage({
    super.key,
    required this.source,
    required this.controller,
    this.credential,
    this.initialSelection = const <CloudRemoteRef>[],
    this.singleSelection = false,
    this.title = '选择夸克目录',
  });

  final CloudSource source;
  final CloudLibraryController controller;
  final CloudCredential? credential;
  final List<CloudRemoteRef> initialSelection;
  final bool singleSelection;
  final String title;

  @override
  Widget build(BuildContext context) {
    return CloudDirectoryPickerPage<List<CloudRemoteRef>>(
      title: title,
      root: const CloudRemoteRef(id: '0', path: '/'),
      initialSelection: initialSelection,
      singleSelection: singleSelection,
      loader: (directory) => controller.browseRemoteDirectories(
        source,
        directory,
        credential: credential,
      ),
      resultBuilder: (selected) => selected,
    );
  }
}
