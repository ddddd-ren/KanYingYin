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
    this.otherBuilder,
    this.otherShowDragHandle = false,
    this.otherUseSafeArea = false,
    this.isScrollControlled = true,
    this.constraints,
    this.clipBehavior = Clip.antiAlias,
  });

  final PlayerOverlayCoordinator coordinator;
  final WidgetBuilder videoInfoBuilder;
  final WidgetBuilder? otherBuilder;
  final Widget child;
  final bool otherShowDragHandle;
  final bool otherUseSafeArea;
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
    final builder = switch (coordinator.visible) {
      PlayerOverlay.videoInfo => widget.videoInfoBuilder,
      PlayerOverlay.other => widget.otherBuilder,
      _ => null,
    };
    if (builder != null) {
      if (_activeRequest?.overlay != coordinator.visible) {
        _closeOwnedSheet();
      }
      _scheduleOverlay(generation, coordinator, coordinator.visible, builder);
    } else {
      _closeOwnedSheet();
    }
  }

  void _scheduleOverlay(
    int generation,
    PlayerOverlayCoordinator coordinator,
    PlayerOverlay overlay,
    WidgetBuilder builder,
  ) {
    if (!mounted || _activeRequest != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _requestGeneration ||
          !identical(widget.coordinator, coordinator) ||
          coordinator.visible != overlay ||
          _activeRequest != null) {
        return;
      }
      unawaited(_showOverlay(generation, coordinator, overlay, builder));
    });
  }

  Future<void> _showOverlay(
    int generation,
    PlayerOverlayCoordinator coordinator,
    PlayerOverlay overlay,
    WidgetBuilder builder,
  ) async {
    final request = _PlayerOverlayRequest(generation, coordinator, overlay);
    _activeRequest = request;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: widget.isScrollControlled,
        showDragHandle: request.overlay == PlayerOverlay.other
            ? widget.otherShowDragHandle
            : null,
        useSafeArea:
            request.overlay == PlayerOverlay.other && widget.otherUseSafeArea,
        constraints: widget.constraints,
        clipBehavior: widget.clipBehavior,
        builder: (context) {
          request
            ..navigator = Navigator.of(context)
            ..route = ModalRoute.of(context);
          if (request.closeRequested ||
              request.generation != _requestGeneration ||
              !identical(widget.coordinator, request.coordinator) ||
              request.coordinator.visible != request.overlay) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _closeRequest(request);
            });
          }
          return builder(context);
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
            request.coordinator.visible == request.overlay) {
          request.coordinator.close(request.overlay);
        } else {
          final currentOverlay = widget.coordinator.visible;
          final currentBuilder = switch (currentOverlay) {
            PlayerOverlay.videoInfo => widget.videoInfoBuilder,
            PlayerOverlay.other => widget.otherBuilder,
            _ => null,
          };
          if (currentBuilder != null) {
            _scheduleOverlay(
              _requestGeneration,
              widget.coordinator,
              currentOverlay,
              currentBuilder,
            );
          }
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
  _PlayerOverlayRequest(this.generation, this.coordinator, this.overlay);

  final int generation;
  final PlayerOverlayCoordinator coordinator;
  final PlayerOverlay overlay;
  NavigatorState? navigator;
  ModalRoute<dynamic>? route;
  bool closeRequested = false;
}
