import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/episode_matching/application/manual_episode_match_controller.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

typedef ManualEpisodeSaveCallback = Future<void> Function(
  TmdbMetadata metadata,
  int seasonNumber,
  List<ManualEpisodeAssignment> assignments,
);

final class ManualEpisodeMatchDialog<TResult> extends StatefulWidget {
  const ManualEpisodeMatchDialog({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final ManualEpisodeMatchController controller;
  final ManualEpisodeSaveCallback onSave;

  @override
  State<ManualEpisodeMatchDialog<TResult>> createState() =>
      _ManualEpisodeMatchDialogState<TResult>();
}

final class _ManualEpisodeMatchDialogState<TResult>
    extends State<ManualEpisodeMatchDialog<TResult>> {
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await widget.controller.initialize();
    } on Object {
      // 控制器已经保存可展示的错误文本。
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final seasonNumber = widget.controller.selectedSeasonNumber;
    if (_saving || seasonNumber == null || !widget.controller.canComplete) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        widget.controller.metadata,
        seasonNumber,
        widget.controller.assignments,
      );
      if (mounted) Navigator.of(context).pop<TResult>();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString().replaceFirst(
              RegExp(r'^\w+(?:Error|Exception):\s*'),
              '',
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = math.min(980.0, math.max(300.0, media.width - 48));
    final height = math.min(720.0, math.max(440.0, media.height - 48));
    return Dialog(
      key: const ValueKey<String>('manual-episode-match-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(context),
            const Divider(height: 1),
            _seasonSelector(context),
            const Divider(height: 1),
            Expanded(child: _body(context)),
            const Divider(height: 1),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final metadata = widget.controller.metadata;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: <Widget>[
          const Icon(Icons.video_collection_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('匹配剧集', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  metadata.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _seasonSelector(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: <Widget>[
          const Text('季度'),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int>(
              key: ValueKey<int?>(controller.selectedSeasonNumber),
              initialValue: controller.selectedSeasonNumber,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              hint: const Text('选择季度'),
              items: controller.availableSeasons
                  .map(
                    (season) => DropdownMenuItem<int>(
                      value: season.seasonNumber,
                      child: Text(
                        season.name.trim().isEmpty
                            ? '第 ${season.seasonNumber} 季'
                            : season.name,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: controller.loadingDetails ||
                      controller.loadingSeason ||
                      _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        unawaited(controller.selectSeason(value));
                      }
                    },
            ),
          ),
          if (controller.loadingDetails || controller.loadingSeason) ...[
            const SizedBox(width: 12),
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    final error = _saveError ?? controller.operationError;
    if (controller.loadingDetails && controller.availableSeasons.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.selectedSeasonNumber == null) {
      return _message(error ?? '请选择季度');
    }
    if (controller.episodes.isEmpty) {
      return _message(error ?? '当前季度没有可匹配的剧集');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: controller.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _resourceRow(context, controller.items[index]),
          ),
        ),
      ],
    );
  }

  Widget _resourceRow(
    BuildContext context,
    ManualEpisodeMatchItem item,
  ) {
    final controller = widget.controller;
    final assignment = controller.assignmentFor(item.resourceId);
    final selected = switch (assignment?.mode) {
      ManualEpisodeAssignmentMode.mapped =>
        'episode:${assignment!.episodeNumber}',
      ManualEpisodeAssignmentMode.keepOriginal => 'keep',
      ManualEpisodeAssignmentMode.restoreAutomatic => 'restore',
      null => null,
    };
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            item.originalName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 330,
          child: DropdownButtonFormField<String>(
            key: ValueKey<String>(
              '${item.resourceId}:${controller.selectedSeasonNumber}:$selected',
            ),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            hint: const Text('未匹配'),
            items: <DropdownMenuItem<String>>[
              for (final episode in controller.episodes)
                DropdownMenuItem<String>(
                  value: 'episode:${episode.episodeNumber}',
                  child: Text(
                    '第 ${episode.episodeNumber} 集 ${episode.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const DropdownMenuItem<String>(
                value: 'keep',
                child: Text('保留原名'),
              ),
              const DropdownMenuItem<String>(
                value: 'restore',
                child: Text('恢复自动识别'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) {
                      controller.clearAssignment(item.resourceId);
                    } else if (value == 'keep') {
                      controller.keepOriginal(item.resourceId);
                    } else if (value == 'restore') {
                      controller.restoreAutomatic(item.resourceId);
                    } else {
                      controller.assignEpisode(
                        item.resourceId,
                        int.parse(value.substring('episode:'.length)),
                      );
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _message(String message) => Center(child: Text(message));

  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: widget.controller.canComplete && !_saving ? _save : null,
            child: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成'),
          ),
        ],
      ),
    );
  }
}
