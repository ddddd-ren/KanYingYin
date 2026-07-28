import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';

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
