import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';

typedef CloudHiddenVideoRestoreCallback = Future<void> Function(
  CloudHiddenVideo record,
);

Future<void> showCloudHiddenVideoManagerDialog({
  required BuildContext context,
  required List<CloudHiddenVideo> records,
  required CloudHiddenVideoRestoreCallback onRestore,
  required Future<void> Function() onRestoreAll,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _CloudHiddenVideoManagerDialog(
        records: records,
        onRestore: onRestore,
        onRestoreAll: onRestoreAll,
      ),
    );

Future<List<CloudFileEntry>?> showCloudHideVideoDialog({
  required BuildContext context,
  required List<CloudFileEntry> videos,
}) {
  if (videos.isEmpty) return Future<List<CloudFileEntry>?>.value(null);
  if (videos.length == 1) {
    final video = videos.single;
    return showDialog<List<CloudFileEntry>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隐藏视频'),
        content: Text(
          '确定从网盘海报墙隐藏“${video.name}”吗？\n\n'
          '只会修改看影音中的显示，不会删除网盘文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              <CloudFileEntry>[video],
            ),
            child: const Text('隐藏'),
          ),
        ],
      ),
    );
  }
  return showDialog<List<CloudFileEntry>>(
    context: context,
    builder: (context) => _CloudHideVideoSelectionDialog(videos: videos),
  );
}

class _CloudHideVideoSelectionDialog extends StatefulWidget {
  const _CloudHideVideoSelectionDialog({required this.videos});

  final List<CloudFileEntry> videos;

  @override
  State<_CloudHideVideoSelectionDialog> createState() =>
      _CloudHideVideoSelectionDialogState();
}

class _CloudHideVideoSelectionDialogState
    extends State<_CloudHideVideoSelectionDialog> {
  final Set<String> _selectedKeys = <String>{};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('cloud-hide-video-dialog'),
      title: const Text('选择要隐藏的视频'),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('隐藏只影响海报墙，不会删除网盘文件。'),
              ),
              for (final video in widget.videos)
                CheckboxListTile(
                  key: ValueKey<String>('hide-video-${video.id}'),
                  value: _selectedKeys.contains(_selectionKey(video)),
                  title: Text(video.name),
                  subtitle: Text(_subtitle(video)),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (selected) {
                    setState(() {
                      final key = _selectionKey(video);
                      if (selected == true) {
                        _selectedKeys.add(key);
                      } else {
                        _selectedKeys.remove(key);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedKeys.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    widget.videos
                        .where(
                          (video) =>
                              _selectedKeys.contains(_selectionKey(video)),
                        )
                        .toList(growable: false),
                  ),
          child: const Text('隐藏所选'),
        ),
      ],
    );
  }

  static String _selectionKey(CloudFileEntry video) =>
      video.id.isNotEmpty ? 'id:${video.id}' : 'path:${video.remotePath}';

  static String _subtitle(CloudFileEntry video) {
    final variant = video.variantLabel?.trim();
    return <String>[
      if (variant != null && variant.isNotEmpty) variant,
      video.remotePath,
    ].join(' · ');
  }
}

class _CloudHiddenVideoManagerDialog extends StatefulWidget {
  const _CloudHiddenVideoManagerDialog({
    required this.records,
    required this.onRestore,
    required this.onRestoreAll,
  });

  final List<CloudHiddenVideo> records;
  final CloudHiddenVideoRestoreCallback onRestore;
  final Future<void> Function() onRestoreAll;

  @override
  State<_CloudHiddenVideoManagerDialog> createState() =>
      _CloudHiddenVideoManagerDialogState();
}

class _CloudHiddenVideoManagerDialogState
    extends State<_CloudHiddenVideoManagerDialog> {
  late List<CloudHiddenVideo> _records;
  String? _busyIdentity;
  bool _restoringAll = false;
  String? _errorMessage;

  bool get _busy => _busyIdentity != null || _restoringAll;

  @override
  void initState() {
    super.initState();
    _records = List<CloudHiddenVideo>.from(widget.records);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('cloud-hidden-video-manager-dialog'),
      title: const Text('管理已隐藏视频'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            if (_records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('当前来源没有已隐藏视频')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final restoring = _busyIdentity == record.identityKey;
                    return ListTile(
                      title: Text(record.fileName),
                      subtitle: Text(record.remotePath),
                      trailing: restoring
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              key: ValueKey<String>(
                                'restore-hidden-video-${record.remoteId}',
                              ),
                              tooltip: '恢复显示',
                              onPressed: _busy ? null : () => _restore(record),
                              icon: const Icon(Icons.visibility_outlined),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_records.isNotEmpty)
          TextButton(
            key: const ValueKey<String>('restore-all-hidden-videos'),
            onPressed: _busy ? null : _confirmRestoreAll,
            child: const Text('全部恢复'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _restore(CloudHiddenVideo record) async {
    setState(() {
      _busyIdentity = record.identityKey;
      _errorMessage = null;
    });
    try {
      await widget.onRestore(record);
      if (!mounted) return;
      setState(() {
        _records.removeWhere(
          (candidate) => candidate.identityKey == record.identityKey,
        );
      });
    } on Object {
      if (!mounted) return;
      setState(() => _errorMessage = '恢复失败，请重试');
    } finally {
      if (mounted) setState(() => _busyIdentity = null);
    }
  }

  Future<void> _confirmRestoreAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全部恢复'),
        content: const Text('确定恢复当前来源的全部隐藏视频吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>(
              'confirm-restore-all-hidden-videos',
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('全部恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _restoringAll = true;
      _errorMessage = null;
    });
    try {
      await widget.onRestoreAll();
      if (!mounted) return;
      setState(_records.clear);
    } on Object {
      if (!mounted) return;
      setState(() => _errorMessage = '恢复失败，请重试');
    } finally {
      if (mounted) setState(() => _restoringAll = false);
    }
  }
}
