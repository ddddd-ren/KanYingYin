import 'dart:async';

import 'package:flutter/material.dart';

enum PlayerOverlay { none, subtitleSettings, videoInfo, other }

@immutable
class PlayerOverlayState {
  const PlayerOverlayState(this.visible);
  final PlayerOverlay visible;
  bool get hasOverlay => visible != PlayerOverlay.none;
}

class PlayerOverlayCoordinator extends ChangeNotifier {
  PlayerOverlayState _state = const PlayerOverlayState(PlayerOverlay.none);
  bool _disposed = false;

  PlayerOverlayState get state => _state;
  PlayerOverlay get visible => _state.visible;

  void open(PlayerOverlay overlay) {
    if (_disposed || overlay == PlayerOverlay.none || visible == overlay) {
      return;
    }
    _state = PlayerOverlayState(overlay);
    notifyListeners();
  }

  void close([PlayerOverlay? overlay]) {
    if (_disposed || visible == PlayerOverlay.none) return;
    if (overlay != null && visible != overlay) return;
    _state = const PlayerOverlayState(PlayerOverlay.none);
    notifyListeners();
  }

  void toggle(PlayerOverlay overlay) {
    if (visible == overlay) {
      close(overlay);
    } else {
      open(overlay);
    }
  }

  void openSubtitleSettings() => open(PlayerOverlay.subtitleSettings);
  void closeSubtitleSettings() => close(PlayerOverlay.subtitleSettings);
  void toggleSubtitleSettings() => toggle(PlayerOverlay.subtitleSettings);
  void openVideoInfo() => open(PlayerOverlay.videoInfo);
  void closeVideoInfo() => close(PlayerOverlay.videoInfo);
  void toggleVideoInfo() => toggle(PlayerOverlay.videoInfo);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PlayerOverlayPresenter extends StatefulWidget {
  const PlayerOverlayPresenter({
    super.key,
    required this.coordinator,
    required this.videoInfoBuilder,
    required this.child,
    this.isScrollControlled = true,
    this.constraints,
    this.clipBehavior = Clip.antiAlias,
  });

  final PlayerOverlayCoordinator coordinator;
  final WidgetBuilder videoInfoBuilder;
  final Widget child;
  final bool isScrollControlled;
  final BoxConstraints? constraints;
  final Clip clipBehavior;

  @override
  State<PlayerOverlayPresenter> createState() => _PlayerOverlayPresenterState();
}

class _PlayerOverlayPresenterState extends State<PlayerOverlayPresenter> {
  NavigatorState? _sheetNavigator;
  bool _sheetOpen = false;
  bool _showScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_handleOverlayChanged);
    _handleOverlayChanged();
  }

  @override
  void didUpdateWidget(PlayerOverlayPresenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator == widget.coordinator) return;
    oldWidget.coordinator.removeListener(_handleOverlayChanged);
    widget.coordinator.addListener(_handleOverlayChanged);
    _handleOverlayChanged();
  }

  void _handleOverlayChanged() {
    if (widget.coordinator.visible == PlayerOverlay.videoInfo) {
      _scheduleVideoInfo();
    } else {
      _closeOwnedSheet();
    }
  }

  void _scheduleVideoInfo() {
    if (!mounted || _sheetOpen || _showScheduled) return;
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || widget.coordinator.visible != PlayerOverlay.videoInfo) {
        return;
      }
      unawaited(_showVideoInfo());
    });
  }

  Future<void> _showVideoInfo() async {
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: widget.isScrollControlled,
      constraints: widget.constraints,
      clipBehavior: widget.clipBehavior,
      builder: (context) {
        _sheetNavigator = Navigator.of(context);
        if (widget.coordinator.visible != PlayerOverlay.videoInfo) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _closeOwnedSheet();
          });
        }
        return widget.videoInfoBuilder(context);
      },
    );
    _sheetOpen = false;
    _sheetNavigator = null;
    if (mounted && widget.coordinator.visible == PlayerOverlay.videoInfo) {
      widget.coordinator.closeVideoInfo();
    }
  }

  void _closeOwnedSheet() {
    final navigator = _sheetNavigator;
    if (navigator == null) return;
    _sheetNavigator = null;
    navigator.pop();
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleOverlayChanged);
    _closeOwnedSheet();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
