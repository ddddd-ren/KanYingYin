import 'dart:async';

import 'package:flutter/material.dart';

typedef LibrarySourceAction = FutureOr<void> Function(
  LibrarySourceViewData source,
);

class LibrarySourceViewData {
  const LibrarySourceViewData({
    required this.id,
    required this.name,
    required this.path,
    required this.subtitle,
    this.isAvailable = true,
    this.isCurrent = false,
  });

  final String id;
  final String name;
  final String path;
  final String subtitle;
  final bool isAvailable;
  final bool isCurrent;
}

class LibrarySourceMenuViewData {
  const LibrarySourceMenuViewData({
    required this.sources,
    this.unavailableCount = 0,
    this.enabled = true,
  });

  final List<LibrarySourceViewData> sources;
  final int unavailableCount;
  final bool enabled;
}

class LibrarySourceMenu extends StatelessWidget {
  const LibrarySourceMenu({
    super.key,
    required this.data,
    required this.onOpen,
    required this.onRemove,
    required this.onRemoveUnavailable,
  });

  final LibrarySourceMenuViewData data;
  final LibrarySourceAction onOpen;
  final LibrarySourceAction onRemove;
  final FutureOr<void> Function() onRemoveUnavailable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<_SourceAction>(
      tooltip: '媒体源',
      icon: const Icon(Icons.video_library_outlined, size: 20),
      enabled: data.enabled && data.sources.isNotEmpty,
      onSelected: (selection) async {
        if (selection.action == _SourceActionType.removeUnavailable) {
          await onRemoveUnavailable();
        } else if (selection.source != null) {
          if (selection.action == _SourceActionType.open) {
            await onOpen(selection.source!);
          } else {
            await onRemove(selection.source!);
          }
        }
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<_SourceAction>>[];
        if (data.unavailableCount > 0) {
          entries
            ..add(PopupMenuItem(
              value: const _SourceAction.removeUnavailable(),
              child: _removeUnavailable(context, colorScheme),
            ))
            ..add(const PopupMenuDivider(height: 6));
        }
        for (var i = 0; i < data.sources.length; i++) {
          final source = data.sources[i];
          entries
            ..add(PopupMenuItem(
              enabled: source.isAvailable,
              value: _SourceAction.open(source),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _sourceItem(context, colorScheme, source),
              ),
            ))
            ..add(PopupMenuItem(
              value: _SourceAction.remove(source),
              child: _removeItem(context, colorScheme, source),
            ));
          if (i < data.sources.length - 1) {
            entries.add(const PopupMenuDivider(height: 6));
          }
        }
        return entries;
      },
    );
  }

  Widget _sourceItem(
      BuildContext context, ColorScheme colors, LibrarySourceViewData source) {
    final iconColor = !source.isAvailable
        ? colors.error
        : source.isCurrent
            ? colors.primary
            : colors.outline;
    return Row(children: [
      Icon(
          !source.isAvailable
              ? Icons.error_outline
              : source.isCurrent
                  ? Icons.check_circle_outline
                  : Icons.folder_outlined,
          size: 20,
          color: iconColor),
      const SizedBox(width: 10),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        source.isCurrent ? FontWeight.w600 : FontWeight.normal,
                    color: source.isAvailable ? null : colors.error)),
            Text(source.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.outline)),
            Text(source.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.outline)),
          ])),
    ]);
  }

  Widget _removeItem(BuildContext context, ColorScheme colors,
          LibrarySourceViewData source) =>
      Row(children: [
        Icon(Icons.delete_outline, size: 20, color: colors.error),
        const SizedBox(width: 10),
        Expanded(
            child: Text('移除“${source.name}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.error))),
      ]);

  Widget _removeUnavailable(BuildContext context, ColorScheme colors) =>
      Row(children: [
        Icon(Icons.cleaning_services_outlined, size: 20, color: colors.error),
        const SizedBox(width: 10),
        Expanded(
            child: Text('清理 ${data.unavailableCount} 个失效媒体源',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.error))),
      ]);
}

class _SourceAction {
  const _SourceAction.open(this.source) : action = _SourceActionType.open;
  const _SourceAction.remove(this.source) : action = _SourceActionType.remove;
  const _SourceAction.removeUnavailable()
      : source = null,
        action = _SourceActionType.removeUnavailable;
  final LibrarySourceViewData? source;
  final _SourceActionType action;
}

enum _SourceActionType { open, remove, removeUnavailable }
