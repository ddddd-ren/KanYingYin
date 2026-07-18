import 'package:flutter/foundation.dart';

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
