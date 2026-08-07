enum PlayerBackAction {
  closeOverlay,
  closeEpisodePanel,
  exitFullscreen,
  leavePlayer,
}

class PlayerBackPolicy {
  const PlayerBackPolicy._();

  static PlayerBackAction decide({
    required bool overlayVisible,
    required bool fullscreen,
    bool episodePanelVisible = false,
    bool controlsVisible = false,
    bool isAndroidTv = false,
  }) {
    if (overlayVisible) return PlayerBackAction.closeOverlay;
    if (isAndroidTv && episodePanelVisible) {
      return PlayerBackAction.closeEpisodePanel;
    }
    if (isAndroidTv && controlsVisible) {
      return PlayerBackAction.closeOverlay;
    }
    if (fullscreen) return PlayerBackAction.exitFullscreen;
    return PlayerBackAction.leavePlayer;
  }
}
