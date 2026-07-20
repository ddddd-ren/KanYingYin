import 'dart:io';
import 'dart:math';

import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_relay_session.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';
import 'package:path/path.dart' as p;

typedef QuarkRangeRelayStarter = Future<QuarkRangeRelayPlayback> Function({
  required QuarkRemoteResource resource,
  required QuarkRemoteResourceRefresher refreshResource,
});

class QuarkRangeRelayPlayback {
  const QuarkRangeRelayPlayback({
    required this.uri,
    required this.lease,
    required this.totalLength,
  });

  final Uri uri;
  final CloudPlaybackLease lease;
  final int totalLength;
}

class QuarkRangeRelayService {
  QuarkRangeRelayService({
    CloudCacheRootProvider? cacheRootProvider,
  }) : _cacheRootProvider = cacheRootProvider ?? defaultCloudCacheRoot;

  static final RegExp _sessionDirectoryPattern =
      RegExp(r'^quark-relay-[0-9a-f]{32}$');

  final CloudCacheRootProvider _cacheRootProvider;
  final Set<CloudPlaybackLease> _leases = <CloudPlaybackLease>{};
  Future<void>? _cleanupFuture;
  bool _closed = false;

  Future<QuarkRangeRelayPlayback> start({
    required QuarkRemoteResource resource,
    required QuarkRemoteResourceRefresher refreshResource,
  }) async {
    if (_closed) throw StateError('夸克中转服务已关闭');
    final cacheRoot = await _cacheRootProvider();
    final relayRoot = CloudCacheDirectories.quarkRelayRoot(cacheRoot);
    await (_cleanupFuture ??= cleanupOrphans(relayRoot));
    if (_closed) throw StateError('夸克中转服务已关闭');

    await relayRoot.create(recursive: true);
    final directory = Directory(
      p.join(relayRoot.path, 'quark-relay-${_randomHex(16)}'),
    );
    await directory.create(recursive: true);
    await File(p.join(directory.path, '.created')).writeAsBytes(const <int>[]);
    final reader = QuarkRangeRemoteReader(
      resource: resource,
      refreshResource: refreshResource,
    );
    final session = await QuarkRangeRelaySession.start(
      reader: reader,
      directory: directory,
    );
    late final _TrackedPlaybackLease lease;
    lease = _TrackedPlaybackLease(
      session,
      onClosed: () => _leases.remove(lease),
    );
    _leases.add(lease);
    return QuarkRangeRelayPlayback(
      uri: session.uri,
      lease: lease,
      totalLength: session.totalLength,
    );
  }

  static Future<void> cleanupOrphans(
    Directory relayRoot, {
    DateTime? now,
  }) async {
    if (!await relayRoot.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(hours: 24));
    await for (final entity in relayRoot.list(followLinks: false)) {
      if (entity is! Directory ||
          !_sessionDirectoryPattern.hasMatch(p.basename(entity.path))) {
        continue;
      }
      try {
        final marker = File(p.join(entity.path, '.created'));
        final stat =
            await marker.exists() ? await marker.stat() : await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } on FileSystemException {
        // 单个孤立目录不可访问时保留，不能阻断新的播放会话。
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final lease in _leases.toList()) {
      await lease.close();
    }
    _leases.clear();
  }

  static String _randomHex(int byteCount) {
    final random = Random.secure();
    return <int>[
      for (var index = 0; index < byteCount; index++) random.nextInt(256),
    ].map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _TrackedPlaybackLease implements CloudPlaybackLease {
  _TrackedPlaybackLease(this._delegate, {required this.onClosed});

  final CloudPlaybackLease _delegate;
  final void Function() onClosed;
  Future<void>? _closeFuture;

  @override
  QuarkRelayStatus get currentStatus => _delegate.currentStatus;

  @override
  Stream<QuarkRelayStatus> get statuses => _delegate.statuses;

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await _delegate.close();
    } finally {
      onClosed();
    }
  }
}
