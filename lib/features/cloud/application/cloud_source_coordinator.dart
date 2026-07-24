import 'dart:async';

import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';

/// 管理网盘来源扫描的互斥、取消与完成等待。
class CloudSourceCoordinator {
  CloudSourceScanHandle? _active;

  String? get activeSourceId => _active?.sourceId;

  CloudSourceScanHandle beginScan(String sourceId) {
    final current = _active;
    if (current != null) {
      throw CloudScanInProgressException(current.sourceId);
    }
    final handle = CloudSourceScanHandle._(this, sourceId);
    _active = handle;
    return handle;
  }

  void cancel(String sourceId) {
    final current = _active;
    if (current?.sourceId == sourceId) current!.token.cancel();
  }

  void cancelActive() {
    _active?.token.cancel();
  }

  Future<void> waitFor(String sourceId) {
    final current = _active;
    return current?.sourceId == sourceId
        ? current!.completed
        : Future<void>.value();
  }

  void _complete(CloudSourceScanHandle handle) {
    if (!identical(_active, handle)) return;
    _active = null;
    handle._complete();
  }
}

class CloudSourceScanHandle {
  CloudSourceScanHandle._(this._owner, this.sourceId);

  final CloudSourceCoordinator _owner;
  final String sourceId;
  final CloudScanCancellationToken token = CloudScanCancellationToken();
  final Completer<void> _completion = Completer<void>();

  Future<void> get completed => _completion.future;

  void complete() => _owner._complete(this);

  void _complete() {
    if (!_completion.isCompleted) _completion.complete();
  }
}
