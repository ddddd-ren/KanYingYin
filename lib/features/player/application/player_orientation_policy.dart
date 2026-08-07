enum PlayerExitOrientation { landscape, portrait }

class PlayerOrientationPolicy {
  const PlayerOrientationPolicy._();

  static PlayerExitOrientation afterPlayback({
    required bool isAndroidTv,
    required bool isTablet,
  }) {
    return isAndroidTv || isTablet
        ? PlayerExitOrientation.landscape
        : PlayerExitOrientation.portrait;
  }
}
