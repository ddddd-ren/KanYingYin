import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';

class EmbeddedTrackMenus extends StatelessWidget {
  const EmbeddedTrackMenus({
    super.key,
    required this.playerController,
    required this.showSubtitleSettings,
    required this.onConfirmTrackLanguage,
    required this.onMenuOpen,
    required this.onMenuClose,
  });

  final PlayerController playerController;
  final VoidCallback showSubtitleSettings;
  final void Function(EmbeddedTrackInfo track) onConfirmTrackLanguage;
  final VoidCallback onMenuOpen;
  final VoidCallback onMenuClose;

  @override
  Widget build(BuildContext context) => Observer(
        builder: (_) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _subtitleMenu(context),
            _audioMenu(context),
          ],
        ),
      );

  Widget _subtitleMenu(BuildContext context) => MenuAnchor(
        consumeOutsideTap: true,
        onOpen: onMenuOpen,
        onClose: onMenuClose,
        builder: (_, controller, __) => TextButton(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Text(
            '字幕',
            style: TextStyle(
              color:
                  playerController.selectedEmbeddedSubtitleTrackId.isNotEmpty ||
                          playerController.currentSubtitlePath.isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
            ),
          ),
        ),
        menuChildren: [
          _menuItem(
            context,
            title: '关闭字幕',
            selected:
                playerController.selectedEmbeddedSubtitleTrackId.isEmpty &&
                    playerController.currentSubtitlePath.isEmpty,
            onPressed: playerController.clearSubtitle,
          ),
          for (final track
              in playerController.availableEmbeddedSubtitleTracks) ...[
            _trackItem(
              context,
              track,
              selected:
                  playerController.selectedEmbeddedSubtitleTrackId == track.id,
              onPressed: () =>
                  playerController.selectEmbeddedSubtitleTrack(track.id),
            ),
            if (!track.isLanguageResolved)
              _menuItem(
                context,
                title: '确认语言',
                onPressed: () => onConfirmTrackLanguage(track),
              ),
          ],
          const Divider(height: 1),
          _menuItem(
            context,
            title: '外部字幕与字幕设置',
            selected: playerController.currentSubtitlePath.isNotEmpty,
            onPressed: showSubtitleSettings,
          ),
        ],
      );

  Widget _audioMenu(BuildContext context) => MenuAnchor(
        consumeOutsideTap: true,
        onOpen: onMenuOpen,
        onClose: onMenuClose,
        builder: (_, controller, __) => TextButton(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: const Text('语言', style: TextStyle(color: Colors.white)),
        ),
        menuChildren: playerController.availableAudioTracks.isEmpty
            ? [
                _menuItem(context, title: '未检测到音轨', onPressed: null),
              ]
            : [
                for (final track in playerController.availableAudioTracks) ...[
                  _trackItem(
                    context,
                    track,
                    selected: playerController.selectedAudioTrackId == track.id,
                    onPressed: () =>
                        playerController.selectAudioTrack(track.id),
                  ),
                  if (!track.isLanguageResolved)
                    _menuItem(
                      context,
                      title: '确认语言',
                      onPressed: () => onConfirmTrackLanguage(track),
                    ),
                ],
              ],
      );

  MenuItemButton _trackItem(
    BuildContext context,
    EmbeddedTrackInfo track, {
    required bool selected,
    required VoidCallback onPressed,
  }) =>
      _menuItem(
        context,
        title: track.primaryLabel,
        subtitle: track.detailLabel,
        selected: selected,
        onPressed: onPressed,
      );

  MenuItemButton _menuItem(
    BuildContext context, {
    required String title,
    String subtitle = '',
    bool selected = false,
    required VoidCallback? onPressed,
  }) =>
      MenuItemButton(
        onPressed: onPressed,
        leadingIcon: SizedBox(
          width: 18,
          child: selected
              ? Icon(Icons.check,
                  size: 18, color: Theme.of(context).colorScheme.primary)
              : null,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      );
}
