import 'package:flutter/foundation.dart';

/// 协调播放页退出，只同步发出一次退出通知。
class PlayerExitCoordinator extends ChangeNotifier {
  bool _exitRequested = false;

  bool get exitRequested => _exitRequested;

  bool beginExit() {
    if (_exitRequested) return false;
    _exitRequested = true;
    notifyListeners();
    return true;
  }
}
