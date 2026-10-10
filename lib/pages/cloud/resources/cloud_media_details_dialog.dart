import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/widgets/tmdb_image_picker_dialog.dart';

Future<void> showCloudMediaDetailsDialog({
  required BuildContext context,
  required CloudMediaIndexItem item,
  AppPlatformCapabilities? capabilities,
  FutureOr<void> Function()? onPlay,
  Future<TmdbImageSet> Function(TmdbImageKind kind)? onLoadImages,
  Future<void> Function(TmdbImageKind kind, String filePath)? onSaveImage,
  Future<void> Function(TmdbImageKind kind)? onClearImage,
}) {
  final platform = capabilities ?? detectAppPlatform();
  if (platform.isAndroid && !platform.isAndroidTv) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CloudMediaDetailsDialog(
        item: item,
        asSheet: true,
        onPlay: onPlay,
        onLoadImages: onLoadImages,
        onSaveImage: onSaveImage,
        onClearImage: onClearImage,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => CloudMediaDetailsDialog(
      item: item,
      onPlay: onPlay,
      onLoadImages: onLoadImages,
      onSaveImage: onSaveImage,
      onClearImage: onClearImage,
    ),
  );
}

class CloudMediaDetailsDialog extends StatefulWidget {
  const CloudMediaDetailsDialog({
    super.key,
    required this.item,
    this.asSheet = false,
    this.onPlay,
    this.onLoadImages,
    this.onSaveImage,
    this.onClearImage,
  });

  final CloudMediaIndexItem item;
  final bool asSheet;
  final FutureOr<void> Function()? onPlay;
  final Future<TmdbImageSet> Function(TmdbImageKind kind)? onLoadImages;
  final Future<void> Function(TmdbImageKind kind, String filePath)? onSaveImage;
  final Future<void> Function(TmdbImageKind kind)? onClearImage;

  @override
  State<CloudMediaDetailsDialog> createState() =>
      _CloudMediaDetailsDialogState();
}

class _CloudMediaDetailsDialogState extends State<CloudMediaDetailsDialog> {
  final Map<TmdbImageKind, String?> _selectedPaths = <TmdbImageKind, String?>{};

  CloudMediaIndexItem get item => widget.item;
  bool get asSheet => widget.asSheet;
  FutureOr<void> Function()? get onPlay => widget.onPlay;
  Future<TmdbImageSet> Function(TmdbImageKind kind)? get onLoadImages =>
      widget.onLoadImages;
  Future<void> Function(TmdbImageKind kind, String filePath)? get onSaveImage =>
      widget.onSaveImage;
  Future<void> Function(TmdbImageKind kind)? get onClearImage =>
      widget.onClearImage;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
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
                    if (item.seasonNumber != null || item.episodeNumber != null)
                      _detail(context, '季集信息', _seasonEpisode(item)),
                    if (_releaseSummary(item).isNotEmpty)
                      _detail(context, '发布规格', _releaseSummary(item)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (onLoadImages != null && onSaveImage != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _imageButton(
                    context,
                    TmdbImageKind.poster,
                    item.seasonNumber == null ? '更换海报' : '更换本季海报',
                  ),
                  _imageButton(context, TmdbImageKind.backdrop, '更换背景图'),
                  if (item.seasonNumber != null && item.episodeNumber != null)
                    _imageButton(context, TmdbImageKind.still, '更换本集剧照'),
                  if (onClearImage != null)
                    _clearButton(context, TmdbImageKind.poster, '恢复海报默认'),
                  if (onClearImage != null)
                    _clearButton(context, TmdbImageKind.backdrop, '恢复背景默认'),
                  if (onClearImage != null &&
                      item.seasonNumber != null &&
                      item.episodeNumber != null)
                    _clearButton(context, TmdbImageKind.still, '恢复剧照默认'),
                ],
              ),
            if (onLoadImages != null && onSaveImage != null)
              const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onPlay != null) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _playAndClose(context),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('播放'),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (asSheet) {
      return SafeArea(
        top: false,
        child: GlassSurface(
          key: const ValueKey<String>('cloud-media-details-dialog'),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: content,
        ),
      );
    }
    return GlassDialog(
      key: const ValueKey<String>('cloud-media-details-dialog'),
      child: content,
    );
  }

  Future<void> _playAndClose(BuildContext context) async {
    Navigator.of(context).pop();
    await onPlay?.call();
  }

  Widget _imageButton(
    BuildContext context,
    TmdbImageKind kind,
    String label,
  ) {
    return OutlinedButton(
      onPressed: () => _pickImage(context, kind, label),
      child: Text(label),
    );
  }

  Widget _clearButton(
    BuildContext context,
    TmdbImageKind kind,
    String label,
  ) {
    return TextButton(
      onPressed: onClearImage == null ? null : () => _clearImage(kind),
      child: Text(label),
    );
  }

  Future<void> _clearImage(TmdbImageKind kind) async {
    final clear = onClearImage;
    if (clear == null) return;
    await clear(kind);
    if (!mounted) return;
    setState(() => _selectedPaths[kind] = null);
  }

  Future<void> _pickImage(
    BuildContext context,
    TmdbImageKind kind,
    String title,
  ) async {
    final load = onLoadImages;
    final save = onSaveImage;
    if (load == null || save == null) return;
    final candidate = await TmdbImagePickerDialog.show(
      context: context,
      title: title,
      kind: kind,
      images: () => load(kind),
      currentPath: _currentPath(kind),
    );
    if (candidate == null || !context.mounted) return;
    await save(kind, candidate.filePath);
    if (!mounted) return;
    setState(
      () => _selectedPaths[kind] = normalizeTmdbImagePath(candidate.filePath),
    );
  }

  String? _currentPath(TmdbImageKind kind) {
    if (_selectedPaths.containsKey(kind)) return _selectedPaths[kind];
    return normalizeTmdbImagePath(
      kind == TmdbImageKind.backdrop
          ? item.tmdbBackdropUrl
          : item.tmdbPosterUrl,
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
