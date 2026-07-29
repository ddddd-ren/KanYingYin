enum PlayerBackAction { closeOverlay, exitFullscreen, leavePlayer }

class PlayerBackPolicy {
  const PlayerBackPolicy._();

  static PlayerBackAction decide({
    required bool overlayVisible,
    required bool fullscreen,
  }) {
    if (overlayVisible) return PlayerBackAction.closeOverlay;
    if (fullscreen) return PlayerBackAction.exitFullscreen;
    return PlayerBackAction.leavePlayer;
  }
}
