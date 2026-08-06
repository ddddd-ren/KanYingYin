import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

enum TvPairingState {
  idle,
  starting,
  active,
  awaitingConfirmation,
  applying,
  success,
  error,
}

@immutable
class TvPairingPendingSummary {
  const TvPairingPendingSummary({
    required this.deviceName,
    required this.cloudSourceCount,
    required this.hasTmdbKey,
  });

  final String deviceName;
  final int cloudSourceCount;
  final bool hasTmdbKey;

  @override
  String toString() =>
      'TvPairingPendingSummary(deviceName: $deviceName, cloudSourceCount: $cloudSourceCount, hasTmdbKey: $hasTmdbKey)';
}

class TvPairingController extends ChangeNotifier with WidgetsBindingObserver {
  TvPairingController({
    required CloudSourceRepository sourceRepository,
    required TmdbCredentialManager tmdbCredentialManager,
    TvPairingServer? server,
    DateTime Function()? now,
  })  : _sourceRepository = sourceRepository,
        _tmdbCredentialManager = tmdbCredentialManager,
        _server = server ?? TvPairingHttpServer(),
        _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  final CloudSourceRepository _sourceRepository;
  final TmdbCredentialManager _tmdbCredentialManager;
  final TvPairingServer _server;
  final DateTime Function() _now;

  TvPairingState _state = TvPairingState.idle;
  TvPairingSession? _session;
  TvPairingServerEndpoint? _endpoint;
  TvPairingPayload? _pendingPayload;
  TvPairingPendingSummary? _pendingSummary;
  Completer<TvPairingSubmissionResult>? _pendingDecision;
  Timer? _countdownTimer;
  String? _errorMessage;
  bool _disposed = false;

  TvPairingState get state => _state;
  TvPairingServerEndpoint? get endpoint => _endpoint;
  TvPairingPendingSummary? get pendingSummary => _pendingSummary;
  String? get errorMessage => _errorMessage;

  Duration get remaining {
    final session = _session;
    if (session == null) return Duration.zero;
    final value = session.expiresAt.difference(_now().toUtc());
    return value.isNegative ? Duration.zero : value;
  }

  Future<void> start() async {
    if (_disposed) return;
    if (_server.isRunning || _session != null) {
      await _stopInternal(notify: false);
    }
    _state = TvPairingState.starting;
    _errorMessage = null;
    _notify();

    final session = TvPairingSession.issue(now: _now().toUtc());
    _session = session;
    try {
      _endpoint = await _server.start(
        session: session,
        onPayload: _handlePayload,
        onCancelled: _handleRemoteCancellation,
      );
      if (_disposed) {
        await _server.stop();
        return;
      }
      _state = TvPairingState.active;
      _startCountdown();
      _notify();
    } on TvPairingNetworkUnavailableException {
      session.cancel();
      _session = null;
      _endpoint = null;
      _state = TvPairingState.error;
      _errorMessage = '未找到可用局域网地址';
      _notify();
    } on Object {
      session.cancel();
      _session = null;
      _endpoint = null;
      _state = TvPairingState.error;
      _errorMessage = '配对服务启动失败';
      _notify();
    }
  }

  Future<void> confirmPending() async {
    final payload = _pendingPayload;
    final decision = _pendingDecision;
    if (payload == null || decision == null || decision.isCompleted) return;

    _state = TvPairingState.applying;
    _errorMessage = null;
    _notify();
    final previousTmdbKey = _tmdbCredentialManager.exportForPairing();
    final shouldUpdateTmdb = payload.tmdbApiKey.isNotEmpty;
    try {
      if (shouldUpdateTmdb) {
        await _tmdbCredentialManager.importForPairing(payload.tmdbApiKey);
      }
      await _sourceRepository.importForPairing(
        payload.cloudSources
            .map(
              (record) => CloudSourcePairingEntry(
                source: record.source,
                credential: record.credential,
              ),
            )
            .toList(growable: false),
      );
      _clearPending();
      _state = TvPairingState.success;
      _countdownTimer?.cancel();
      decision.complete(TvPairingSubmissionResult.accepted);
      _notify();
    } on Object {
      if (shouldUpdateTmdb) {
        try {
          await _tmdbCredentialManager.importForPairing(previousTmdbKey);
        } on Object {
          // 保持错误信息脱敏，恢复失败由用户在手动配置页重新确认。
        }
      }
      _clearPending();
      _state = TvPairingState.error;
      _errorMessage = '配置写入失败，请重试';
      decision.complete(TvPairingSubmissionResult.rejected);
      _notify();
    }
  }

  void rejectPending() {
    final decision = _pendingDecision;
    if (decision == null || decision.isCompleted) return;
    _clearPending();
    _state = TvPairingState.active;
    decision.complete(TvPairingSubmissionResult.rejected);
    _notify();
  }

  Future<void> cancel() => _stopInternal(notify: true);

  Future<void> _stopInternal({required bool notify}) async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final decision = _pendingDecision;
    _clearPending();
    if (decision != null && !decision.isCompleted) {
      decision.complete(TvPairingSubmissionResult.rejected);
    }
    _session?.cancel();
    _session = null;
    _endpoint = null;
    if (_server.isRunning) await _server.stop();
    _state = TvPairingState.idle;
    _errorMessage = null;
    if (notify) _notify();
  }

  Future<TvPairingSubmissionResult> _handlePayload(
    TvPairingPayload payload,
  ) async {
    if (_disposed || _state != TvPairingState.active) {
      return TvPairingSubmissionResult.rejected;
    }
    final decision = Completer<TvPairingSubmissionResult>();
    _pendingPayload = payload;
    _pendingSummary = TvPairingPendingSummary(
      deviceName: payload.deviceName,
      cloudSourceCount: payload.cloudSources.length,
      hasTmdbKey: payload.tmdbApiKey.isNotEmpty,
    );
    _pendingDecision = decision;
    _state = TvPairingState.awaitingConfirmation;
    _notify();
    return decision.future;
  }

  Future<void> _handleRemoteCancellation() async {
    final decision = _pendingDecision;
    _clearPending();
    if (decision != null && !decision.isCompleted) {
      decision.complete(TvPairingSubmissionResult.rejected);
    }
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _session = null;
    _endpoint = null;
    _state = TvPairingState.idle;
    _errorMessage = null;
    _notify();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = _session;
      if (session == null) return;
      if (session.isExpired(_now().toUtc())) {
        unawaited(_expire());
      } else {
        _notify();
      }
    });
  }

  Future<void> _expire() async {
    final decision = _pendingDecision;
    _clearPending();
    if (decision != null && !decision.isCompleted) {
      decision.complete(TvPairingSubmissionResult.rejected);
    }
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _session?.cancel();
    _session = null;
    _endpoint = null;
    if (_server.isRunning) await _server.stop();
    _state = TvPairingState.error;
    _errorMessage = '配对已超时，请重试';
    _notify();
  }

  void _clearPending() {
    _pendingPayload = null;
    _pendingSummary = null;
    _pendingDecision = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_stopInternal(notify: true));
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _countdownTimer?.cancel();
    final decision = _pendingDecision;
    _clearPending();
    if (decision != null && !decision.isCompleted) {
      decision.complete(TvPairingSubmissionResult.rejected);
    }
    _session?.cancel();
    _session = null;
    _endpoint = null;
    if (_server.isRunning) unawaited(_server.stop());
    super.dispose();
  }

  @override
  String toString() =>
      'TvPairingController(state: $_state, endpoint: $_endpoint)';
}
