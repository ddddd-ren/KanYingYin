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
  bool get blocksPlayerMouseWheelVolume =>
      visible == PlayerOverlay.subtitleSettings;

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
  _PlayerOverlayRequest? _activeRequest;
  int _requestGeneration = 0;

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
    _requestGeneration++;
    oldWidget.coordinator.removeListener(_handleOverlayChanged);
    _closeOwnedSheet();
    widget.coordinator.addListener(_handleOverlayChanged);
    _handleOverlayChanged();
  }

  void _handleOverlayChanged() {
    final generation = ++_requestGeneration;
    final coordinator = widget.coordinator;
    if (coordinator.visible == PlayerOverlay.videoInfo) {
      _scheduleVideoInfo(generation, coordinator);
    } else {
      _closeOwnedSheet();
    }
  }

  void _scheduleVideoInfo(
    int generation,
    PlayerOverlayCoordinator coordinator,
  ) {
    if (!mounted || _activeRequest != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _requestGeneration ||
          !identical(widget.coordinator, coordinator) ||
          coordinator.visible != PlayerOverlay.videoInfo ||
          _activeRequest != null) {
        return;
      }
      unawaited(_showVideoInfo(generation, coordinator));
    });
  }

  Future<void> _showVideoInfo(
    int generation,
    PlayerOverlayCoordinator coordinator,
  ) async {
    final request = _PlayerOverlayRequest(generation, coordinator);
    _activeRequest = request;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: widget.isScrollControlled,
        constraints: widget.constraints,
        clipBehavior: widget.clipBehavior,
        builder: (context) {
          request
            ..navigator = Navigator.of(context)
            ..route = ModalRoute.of(context);
          if (request.closeRequested ||
              request.generation != _requestGeneration ||
              !identical(widget.coordinator, request.coordinator) ||
              request.coordinator.visible != PlayerOverlay.videoInfo) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _closeRequest(request);
            });
          }
          return widget.videoInfoBuilder(context);
        },
      );
    } finally {
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
      if (mounted) {
        final isCurrentRequest = request.generation == _requestGeneration &&
            identical(widget.coordinator, request.coordinator);
        if (isCurrentRequest &&
            request.coordinator.visible == PlayerOverlay.videoInfo) {
          request.coordinator.closeVideoInfo();
        } else if (widget.coordinator.visible == PlayerOverlay.videoInfo) {
          _scheduleVideoInfo(_requestGeneration, widget.coordinator);
        }
      }
    }
  }

  void _closeOwnedSheet() {
    final request = _activeRequest;
    if (request == null) return;
    request.closeRequested = true;
    _closeRequest(request);
  }

  void _closeRequest(_PlayerOverlayRequest request) {
    final navigator = request.navigator;
    final route = request.route;
    if (navigator == null || route == null || !route.isActive) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    widget.coordinator.removeListener(_handleOverlayChanged);
    _closeOwnedSheet();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PlayerOverlayRequest {
  _PlayerOverlayRequest(this.generation, this.coordinator);

  final int generation;
  final PlayerOverlayCoordinator coordinator;
  NavigatorState? navigator;
  ModalRoute<dynamic>? route;
  bool closeRequested = false;
}
