import 'dart:io';
import 'dart:math';

import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_session.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

typedef CloudRangeRelayStarter = Future<CloudRangeRelayPlayback> Function({
  required CloudRangeRemoteReader reader,
  required String providerKey,
  required String providerName,
  required CloudSourceType providerType,
});

class CloudRangeRelayPlayback {
  const CloudRangeRelayPlayback({
    required this.uri,
    required this.lease,
    required this.totalLength,
  });

  final Uri uri;
  final CloudPlaybackLease lease;
  final int totalLength;
}

class CloudRangeRelayService {
  CloudRangeRelayService({
    CloudCacheRootProvider? cacheRootProvider,
    AppPlatformCapabilities? capabilities,
  })  : _cacheRootProvider = cacheRootProvider ?? defaultCloudCacheRoot,
        _capabilities = capabilities ?? detectAppPlatform();

  static final RegExp _sessionDirectoryPattern =
      RegExp(r'^cloud-relay-[0-9a-f]{32}$');

  static CloudRangeRelayTuning tuningFor({
    required AppPlatformCapabilities capabilities,
    required CloudSourceType providerType,
  }) {
    if (!capabilities.isAndroid) return CloudRangeRelayTuning.windows;
    if (capabilities.isAndroidTv) return CloudRangeRelayTuning.androidTv;
    if (providerType == CloudSourceType.quark &&
        capabilities.usesMt6877QuarkTuning) {
      return CloudRangeRelayTuning.androidQuarkMt6877;
    }
    return switch (providerType) {
      CloudSourceType.quark => CloudRangeRelayTuning.androidQuarkAdaptive,
      CloudSourceType.baidu => CloudRangeRelayTuning.androidHighThroughput,
      _ => CloudRangeRelayTuning.android,
    };
  }

  final CloudCacheRootProvider _cacheRootProvider;
  final AppPlatformCapabilities _capabilities;
  final Set<CloudPlaybackLease> _leases = <CloudPlaybackLease>{};
  final Map<String, Future<void>> _cleanupFutures = <String, Future<void>>{};
  bool _closed = false;

  Future<CloudRangeRelayPlayback> start({
    required CloudRangeRemoteReader reader,
    required String providerKey,
    required String providerName,
    required CloudSourceType providerType,
  }) async {
    if (_closed) throw StateError('云盘中转服务已关闭');
    final normalizedProviderKey = providerKey.trim();
    final normalizedProviderName = providerName.trim();
    if (normalizedProviderKey.isEmpty || normalizedProviderName.isEmpty) {
      await reader.close();
      throw ArgumentError('提供方标识和名称不能为空');
    }
    final cacheRoot = await _cacheRootProvider();
    final relayRoot = CloudCacheDirectories.cloudRangeRelayProvider(
      cacheRoot,
      normalizedProviderKey,
    );
    await _cleanupFutures.putIfAbsent(
      relayRoot.path,
      () => cleanupOrphans(relayRoot),
    );
    if (_closed) {
      await reader.close();
      throw StateError('云盘中转服务已关闭');
    }

    await relayRoot.create(recursive: true);
    final directory = Directory(
      p.join(relayRoot.path, 'cloud-relay-${_randomHex(16)}'),
    );
    try {
      await directory.create(recursive: true);
      await File(p.join(directory.path, '.created'))
          .writeAsBytes(const <int>[]);
      final tuning = tuningFor(
        capabilities: _capabilities,
        providerType: providerType,
      );
      AppLogger().i(
        'CloudRangeRelayService: provider=$normalizedProviderName '
        'profile=${_capabilities.androidPerformanceProfile.name} '
        'chunkMiB=${tuning.chunkSize ~/ (1024 * 1024)} '
        'baseReads=${tuning.maxConcurrentReads} '
        'boostReads=${tuning.adaptivePolicy?.maxConcurrentReads ?? tuning.maxConcurrentReads}',
      );
      final session = await CloudRangeRelaySession.start(
        reader: reader,
        directory: directory,
        providerName: normalizedProviderName,
        tuning: tuning,
      );
      late final _TrackedPlaybackLease lease;
      lease = _TrackedPlaybackLease(
        session,
        onClosed: () => _leases.remove(lease),
      );
      _leases.add(lease);
      return CloudRangeRelayPlayback(
        uri: session.uri,
        lease: lease,
        totalLength: session.totalLength,
      );
    } on Object {
      await reader.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
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
  CloudRangeRelayStatus get currentStatus => _delegate.currentStatus;

  @override
  Stream<CloudRangeRelayStatus> get statuses => _delegate.statuses;

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
