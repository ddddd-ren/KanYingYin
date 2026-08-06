enum TvRemoteAction {
  activate,
  playPause,
  seekBackward,
  seekForward,
  volumeUp,
  volumeDown,
  back,
  menu,
}

enum TvRemoteRoute {
  ignored,
  playPause,
  seekBackward,
  seekForward,
  volumeUp,
  volumeDown,
  focusControls,
  hideControls,
  back,
  menu,
}

class TvRemoteKeyPolicy {
  const TvRemoteKeyPolicy._();

  static const Map<String, TvRemoteAction> _actions = {
    'enter': TvRemoteAction.activate,
    'select': TvRemoteAction.activate,
    'gamebuttona': TvRemoteAction.activate,
    'numpadenter': TvRemoteAction.activate,
    'media play pause': TvRemoteAction.playPause,
    'mediaplaypause': TvRemoteAction.playPause,
    'media play': TvRemoteAction.playPause,
    'media pause': TvRemoteAction.playPause,
    'play pause': TvRemoteAction.playPause,
    'arrow left': TvRemoteAction.seekBackward,
    'arrow right': TvRemoteAction.seekForward,
    'arrow up': TvRemoteAction.volumeUp,
    'arrow down': TvRemoteAction.volumeDown,
    'escape': TvRemoteAction.back,
    'back': TvRemoteAction.back,
    'browserback': TvRemoteAction.back,
    'go back': TvRemoteAction.back,
    'menu': TvRemoteAction.menu,
    'contextmenu': TvRemoteAction.menu,
  };

  static TvRemoteAction? actionFor(String keyLabel) {
    final normalized = keyLabel.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return _actions[normalized];
  }

  static TvRemoteRoute routeFor(
    String keyLabel, {
    required bool controlsVisible,
    required bool controlsFocused,
  }) {
    final action = actionFor(keyLabel);
    if (action == null) return TvRemoteRoute.ignored;
    if (controlsFocused) {
      return switch (action) {
        TvRemoteAction.playPause => TvRemoteRoute.playPause,
        TvRemoteAction.back => TvRemoteRoute.back,
        TvRemoteAction.menu => TvRemoteRoute.menu,
        _ => TvRemoteRoute.ignored,
      };
    }
    if (controlsVisible) {
      return switch (action) {
        TvRemoteAction.seekBackward ||
        TvRemoteAction.seekForward ||
        TvRemoteAction.volumeUp ||
        TvRemoteAction.volumeDown =>
          TvRemoteRoute.focusControls,
        TvRemoteAction.back => TvRemoteRoute.hideControls,
        TvRemoteAction.activate ||
        TvRemoteAction.playPause =>
          TvRemoteRoute.playPause,
        TvRemoteAction.menu => TvRemoteRoute.menu,
      };
    }
    return switch (action) {
      TvRemoteAction.activate ||
      TvRemoteAction.playPause =>
        TvRemoteRoute.playPause,
      TvRemoteAction.seekBackward => TvRemoteRoute.seekBackward,
      TvRemoteAction.seekForward => TvRemoteRoute.seekForward,
      TvRemoteAction.volumeUp => TvRemoteRoute.volumeUp,
      TvRemoteAction.volumeDown => TvRemoteRoute.volumeDown,
      TvRemoteAction.back => TvRemoteRoute.back,
      TvRemoteAction.menu => TvRemoteRoute.menu,
    };
  }
}
