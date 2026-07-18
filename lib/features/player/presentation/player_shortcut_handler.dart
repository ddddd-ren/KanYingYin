import 'dart:async';

enum PlayerShortcutPhase { down, repeat, up }

enum PlayerShortcutAction {
  playOrPause,
  forward,
  rewind,
  next,
  prev,
  volumeUp,
  volumeDown,
  toggleMute,
  fullscreen,
  screenshot,
  skip,
  exitFullscreen,
  speed1,
  speed2,
  speed3,
  speedUp,
  speedDown,
  forwardRepeat,
  forwardUp,
}

extension PlayerShortcutActionCommand on PlayerShortcutAction {
  String get command => switch (this) {
        PlayerShortcutAction.playOrPause => 'playorpause',
        PlayerShortcutAction.forward => 'forward',
        PlayerShortcutAction.rewind => 'rewind',
        PlayerShortcutAction.next => 'next',
        PlayerShortcutAction.prev => 'prev',
        PlayerShortcutAction.volumeUp => 'volumeup',
        PlayerShortcutAction.volumeDown => 'volumedown',
        PlayerShortcutAction.toggleMute => 'togglemute',
        PlayerShortcutAction.fullscreen => 'fullscreen',
        PlayerShortcutAction.screenshot => 'screenshot',
        PlayerShortcutAction.skip => 'skip',
        PlayerShortcutAction.exitFullscreen => 'exitfullscreen',
        PlayerShortcutAction.speed1 => 'speed1',
        PlayerShortcutAction.speed2 => 'speed2',
        PlayerShortcutAction.speed3 => 'speed3',
        PlayerShortcutAction.speedUp => 'speedup',
        PlayerShortcutAction.speedDown => 'speeddown',
        PlayerShortcutAction.forwardRepeat => 'forwardRepeat',
        PlayerShortcutAction.forwardUp => 'forwardUp',
      };
}

typedef PlayerShortcutCallback = FutureOr<void> Function(
  PlayerShortcutAction action,
);

class PlayerShortcutDispatchResult {
  const PlayerShortcutDispatchResult._({
    required this.consumed,
    required this.phase,
    this.action,
  });

  const PlayerShortcutDispatchResult.ignored(PlayerShortcutPhase phase)
      : this._(consumed: false, phase: phase);

  const PlayerShortcutDispatchResult.handled(
    PlayerShortcutPhase phase,
    PlayerShortcutAction action,
  ) : this._(consumed: true, phase: phase, action: action);

  final bool consumed;
  final PlayerShortcutPhase phase;
  final PlayerShortcutAction? action;
}

class PlayerShortcutHandler {
  PlayerShortcutHandler({
    required Map<String, List<String>> shortcuts,
    required this.dispatch,
    Set<String>? longPressActions,
  })  : _shortcuts = _copy(shortcuts),
        _longPressActions = longPressActions ?? const {'forward'};

  factory PlayerShortcutHandler.fromConfig({
    required Map<String, Object?> shortcuts,
    required PlayerShortcutCallback dispatch,
    Set<String>? longPressActions,
  }) {
    return PlayerShortcutHandler(
      shortcuts: _parse(shortcuts),
      dispatch: dispatch,
      longPressActions: longPressActions,
    );
  }

  final PlayerShortcutCallback dispatch;
  final Map<String, List<String>> _shortcuts;
  final Set<String> _longPressActions;

  PlayerShortcutDispatchResult dispatchKey(
    String keyLabel,
    PlayerShortcutPhase phase,
  ) {
    if (keyLabel.isEmpty) return PlayerShortcutDispatchResult.ignored(phase);
    if (phase == PlayerShortcutPhase.down) {
      for (final entry in _shortcuts.entries) {
        if (entry.value.contains(keyLabel)) {
          final action = _actionFor(entry.key);
          if (action == null) continue;
          dispatch(action);
          return PlayerShortcutDispatchResult.handled(phase, action);
        }
      }
      return PlayerShortcutDispatchResult.ignored(phase);
    }
    final suffix = phase == PlayerShortcutPhase.repeat ? 'Repeat' : 'Up';
    for (final function in _longPressActions) {
      if (_shortcuts[function]?.contains(keyLabel) != true) continue;
      final action = _actionFor('$function$suffix');
      if (action == null) continue;
      dispatch(action);
      return PlayerShortcutDispatchResult.handled(phase, action);
    }
    return PlayerShortcutDispatchResult.ignored(phase);
  }

  bool handleKey(String keyLabel, PlayerShortcutPhase phase) =>
      dispatchKey(keyLabel, phase).consumed;

  bool handleShortcutDown(String keyLabel) =>
      handleKey(keyLabel, PlayerShortcutPhase.down);

  bool handleShortcutLongPress(String keyLabel, String mode) {
    final phase = switch (mode.toLowerCase()) {
      'repeat' => PlayerShortcutPhase.repeat,
      'up' => PlayerShortcutPhase.up,
      _ => null,
    };
    return phase != null && handleKey(keyLabel, phase);
  }

  static Map<String, List<String>> _copy(Map<String, List<String>> source) =>
      <String, List<String>>{
        for (final entry in source.entries)
          entry.key: List<String>.from(entry.value),
      };

  static Map<String, List<String>> _parse(Map<String, Object?> source) {
    return <String, List<String>>{
      for (final entry in source.entries)
        entry.key: switch (entry.value) {
          Iterable<Object?> values => values
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
          _ => const <String>[],
        },
    };
  }

  static PlayerShortcutAction? _actionFor(String name) {
    const actions = <String, PlayerShortcutAction>{
      'playorpause': PlayerShortcutAction.playOrPause,
      'forward': PlayerShortcutAction.forward,
      'rewind': PlayerShortcutAction.rewind,
      'next': PlayerShortcutAction.next,
      'prev': PlayerShortcutAction.prev,
      'volumeup': PlayerShortcutAction.volumeUp,
      'volumedown': PlayerShortcutAction.volumeDown,
      'togglemute': PlayerShortcutAction.toggleMute,
      'fullscreen': PlayerShortcutAction.fullscreen,
      'screenshot': PlayerShortcutAction.screenshot,
      'skip': PlayerShortcutAction.skip,
      'exitfullscreen': PlayerShortcutAction.exitFullscreen,
      'speed1': PlayerShortcutAction.speed1,
      'speed2': PlayerShortcutAction.speed2,
      'speed3': PlayerShortcutAction.speed3,
      'speedup': PlayerShortcutAction.speedUp,
      'speeddown': PlayerShortcutAction.speedDown,
      'forwardRepeat': PlayerShortcutAction.forwardRepeat,
      'forwardUp': PlayerShortcutAction.forwardUp,
    };
    return actions[name];
  }
}
