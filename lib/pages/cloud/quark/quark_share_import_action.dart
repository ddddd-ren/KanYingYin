import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';

/// 媒体库中的夸克分享导入入口，凭据判断由网盘控制器统一完成。
class QuarkShareImportAction extends StatefulWidget {
  const QuarkShareImportAction({
    super.key,
    required this.controller,
    this.onImport,
  });

  final CloudLibraryController controller;
  final void Function(CloudSource source)? onImport;

  @override
  State<QuarkShareImportAction> createState() => _QuarkShareImportActionState();
}

class _QuarkShareImportActionState extends State<QuarkShareImportAction> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.controller.load();
  }

  @override
  void didUpdateWidget(covariant QuarkShareImportAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<CloudSource> get _usableSources => widget.controller.sources
      .where((source) =>
          source.type == CloudSourceType.quark &&
          source.enabled &&
          widget.controller.isQuarkSourceUsable(source.id))
      .toList(growable: false);

  Future<void> _chooseSource() async {
    final sources = _usableSources;
    if (sources.isEmpty) return;
    CloudSource? source;
    if (sources.length == 1) {
      source = sources.single;
    } else {
      source = await showModalBottomSheet<CloudSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(title: Text('选择夸克网盘来源')),
            for (final item in sources)
              ListTile(
                leading: const Icon(Icons.cloud_queue_outlined),
                title: Text(item.name),
                onTap: () => Navigator.of(context).pop(item),
              ),
          ],
        ),
      );
    }
    if (source == null || !mounted) return;
    final onImport = widget.onImport;
    if (onImport != null) {
      onImport(source);
      return;
    }
    Modular.to.pushNamed(
      '/settings/cloud-sources/quark/import',
      arguments: source,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_usableSources.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: '导入夸克分享',
      onPressed: _chooseSource,
      icon: const Icon(Icons.drive_folder_upload_outlined),
    );
  }
}
