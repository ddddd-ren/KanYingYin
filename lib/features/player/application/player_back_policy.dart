enum PlayerBackAction { closeOverlay, exitFullscreen, leavePlayer }

class PlayerBackPolicy {
  const PlayerBackPolicy._();

  static PlayerBackAction decide({
    required bool overlayVisible,
    required bool fullscreen,
    bool controlsVisible = false,
    bool isAndroidTv = false,
  }) {
    if (overlayVisible) return PlayerBackAction.closeOverlay;
    if (isAndroidTv && controlsVisible) {
      return PlayerBackAction.closeOverlay;
    }
    if (fullscreen) return PlayerBackAction.exitFullscreen;
    return PlayerBackAction.leavePlayer;
  }
}
