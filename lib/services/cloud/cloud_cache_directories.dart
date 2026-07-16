import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef CloudCacheRootProvider = Future<Directory> Function();

Future<Directory> defaultCloudCacheRoot() => getApplicationCacheDirectory();

class CloudCacheDirectories {
  const CloudCacheDirectories._();

  static Directory posterRoot(Directory cacheRoot) =>
      Directory(p.join(cacheRoot.path, 'cloud_posters'));

  static Directory subtitleRoot(Directory cacheRoot) =>
      Directory(p.join(cacheRoot.path, 'cloud_subtitles'));

  static Directory posterSource(Directory cacheRoot, String sourceId) =>
      Directory(p.join(posterRoot(cacheRoot).path, sourceSegment(sourceId)));

  static Directory subtitleSource(Directory cacheRoot, String sourceId) =>
      Directory(p.join(subtitleRoot(cacheRoot).path, sourceSegment(sourceId)));

  static String sourceSegment(String sourceId) =>
      sha256.convert(utf8.encode(sourceId)).toString();
}

class CloudCacheOperationLease {
  CloudCacheOperationLease._(this._key, this._state, this._generation);

  final String _key;
  final _CloudCacheOperationState _state;
  final int _generation;
  bool _released = false;

  bool get isCurrent =>
      !_released && !_state.clearing && _state.generation == _generation;

  void release() {
    if (_released) return;
    _released = true;
    CloudCacheOperationCoordinator._release(_key, _state);
  }
}

class CloudCacheOperationCoordinator {
  const CloudCacheOperationCoordinator._();

  static final Map<String, _CloudCacheOperationState> _states =
      <String, _CloudCacheOperationState>{};

  static CloudCacheOperationLease? tryBegin(Directory sourceDirectory) {
    final key = _key(sourceDirectory);
    final state = _states.putIfAbsent(key, _CloudCacheOperationState.new);
    if (state.clearing) return null;
    state.activeOperations++;
    return CloudCacheOperationLease._(key, state, state.generation);
  }

  static Future<void> clearSource(Directory sourceDirectory) {
    final key = _key(sourceDirectory);
    final state = _states.putIfAbsent(key, _CloudCacheOperationState.new);
    final existing = state.clearOperation;
    if (existing != null) return existing;
    final operation = _clear(key, state, sourceDirectory);
    state.clearOperation = operation;
    return operation;
  }

  static Future<void> _clear(
    String key,
    _CloudCacheOperationState state,
    Directory sourceDirectory,
  ) async {
    state.clearing = true;
    state.generation++;
    try {
      if (state.activeOperations > 0) {
        state.idle = Completer<void>();
        await state.idle!.future;
      }
      if (await sourceDirectory.exists()) {
        await sourceDirectory.delete(recursive: true);
      }
    } finally {
      state.clearing = false;
      state.idle = null;
      state.clearOperation = null;
      if (identical(_states[key], state)) _states.remove(key);
    }
  }

  static void _release(String key, _CloudCacheOperationState state) {
    if (state.activeOperations > 0) state.activeOperations--;
    if (state.activeOperations == 0 && state.idle?.isCompleted == false) {
      state.idle!.complete();
    }
    if (state.activeOperations == 0 &&
        !state.clearing &&
        state.clearOperation == null &&
        identical(_states[key], state)) {
      _states.remove(key);
    }
  }

  static String _key(Directory directory) => Platform.isWindows
      ? p.normalize(directory.absolute.path).toLowerCase()
      : p.normalize(directory.absolute.path);
}

class _CloudCacheOperationState {
  int generation = 0;
  int activeOperations = 0;
  bool clearing = false;
  Completer<void>? idle;
  Future<void>? clearOperation;
}
