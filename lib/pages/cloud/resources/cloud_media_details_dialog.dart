import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';

Future<void> showCloudMediaDetailsDialog({
  required BuildContext context,
  required CloudMediaIndexItem item,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => CloudMediaDetailsDialog(item: item),
  );
}

class CloudMediaDetailsDialog extends StatelessWidget {
  const CloudMediaDetailsDialog({super.key, required this.item});

  final CloudMediaIndexItem item;

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      key: const ValueKey<String>('cloud-media-details-dialog'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '媒体详情',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _detail(context, '虚拟名称', item.displayName),
                      _detail(context, '作品标题', item.seriesName),
                      _detail(context, '网盘原名', item.remoteName),
                      _detail(context, '网盘路径', item.remotePath),
                      if (item.seasonNumber != null ||
                          item.episodeNumber != null)
                        _detail(context, '季集信息', _seasonEpisode(item)),
                      if (_releaseSummary(item).isNotEmpty)
                        _detail(context, '发布规格', _releaseSummary(item)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }

  String _seasonEpisode(CloudMediaIndexItem item) {
    final season = item.seasonNumber;
    final episode = item.episodeNumber;
    if (season != null && episode != null) {
      return 'S${season.toString().padLeft(2, '0')}'
          'E${episode.toString().padLeft(2, '0')}';
    }
    if (season != null) return '第 $season 季';
    return '第 $episode 集';
  }

  String _releaseSummary(CloudMediaIndexItem item) {
    final tags = item.releaseTags;
    return <String?>[
      tags.resolution,
      tags.source,
      tags.codec,
      ...tags.dynamicRange,
      ...tags.audio,
      tags.releaseGroup,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
  }
}
