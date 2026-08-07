import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';

enum TvPairingState {
  idle,
  starting,
  active,
  phoneConnected,
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
    required this.added,
    required this.updated,
    required this.preserved,
    required this.requiresRootSelection,
  });

  final String deviceName;
  final int cloudSourceCount;
  final bool hasTmdbKey;
  final int added;
  final int updated;
  final int preserved;
  final int requiresRootSelection;

  @override
  String toString() => 'TvPairingPendingSummary(deviceName: $deviceName, '
      'cloudSourceCount: $cloudSourceCount, hasTmdbKey: $hasTmdbKey, '
      'added: $added, updated: $updated, preserved: $preserved, '
      'requiresRootSelection: $requiresRootSelection)';
}

class TvPairingController extends ChangeNotifier with WidgetsBindingObserver {
  TvPairingController({
    required ConfigurationImportPort importer,
    TvPairingServer? server,
    DateTime Function()? now,
  })  : _importer = importer,
        _server = server ?? TvPairingHttpServer(),
        _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  final ConfigurationImportPort _importer;
  final TvPairingServer _server;
  final DateTime Function() _now;

  TvPairingState _state = TvPairingState.idle;
  TvPairingSession? _session;
  TvPairingServerEndpoint? _endpoint;
  TvPairingPayload? _pendingPayload;
  TvPairingPendingSummary? _pendingSummary;
  ConfigurationMergeSummary? _completedSummary;
  Completer<TvPairingSubmissionResult>? _pendingDecision;
  Timer? _countdownTimer;
  String? _errorMessage;
  bool _phoneConnected = false;
  bool _disposed = false;

  TvPairingState get state => _state;
  TvPairingServerEndpoint? get endpoint => _endpoint;
  TvPairingPendingSummary? get pendingSummary => _pendingSummary;
  ConfigurationMergeSummary? get completedSummary => _completedSummary;
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
    _completedSummary = null;
    _phoneConnected = false;
    _notify();

    final session = TvPairingSession.issue(now: _now().toUtc());
    _session = session;
    try {
      _endpoint = await _server.start(
        session: session,
        onPhoneConnected: _handlePhoneConnected,
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
    try {
      final result = await _importer.apply(payload.configuration);
      _completedSummary = result;
      _clearPending();
      _state = TvPairingState.success;
      _countdownTimer?.cancel();
      decision.complete(TvPairingSubmissionResult.accepted);
      _notify();
    } on ConfigurationRollbackException {
      _clearPending();
      _state = TvPairingState.error;
      _errorMessage = '配置写入失败，自动恢复未完整完成';
      decision.complete(TvPairingSubmissionResult.applyFailed);
      _notify();
    } on Object {
      _clearPending();
      _state = TvPairingState.error;
      _errorMessage = '配置写入失败，原配置已保留';
      decision.complete(TvPairingSubmissionResult.applyFailed);
      _notify();
    }
  }

  void rejectPending() {
    final decision = _pendingDecision;
    if (decision == null || decision.isCompleted) return;
    _clearPending();
    _state =
        _phoneConnected ? TvPairingState.phoneConnected : TvPairingState.active;
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
    _phoneConnected = false;
    _completedSummary = null;
    if (_server.isRunning) await _server.stop();
    _state = TvPairingState.idle;
    _errorMessage = null;
    if (notify) _notify();
  }

  void _handlePhoneConnected() {
    if (_disposed || _state != TvPairingState.active) return;
    _phoneConnected = true;
    _state = TvPairingState.phoneConnected;
    _errorMessage = null;
    _notify();
  }

  Future<TvPairingSubmissionResult> _handlePayload(
    TvPairingPayload payload,
  ) async {
    if (_disposed ||
        (_state != TvPairingState.active &&
            _state != TvPairingState.phoneConnected)) {
      return TvPairingSubmissionResult.rejected;
    }
    final summary = await _importer.preview(payload.configuration);
    final decision = Completer<TvPairingSubmissionResult>();
    _pendingPayload = payload;
    _pendingSummary = TvPairingPendingSummary(
      deviceName: payload.deviceName,
      cloudSourceCount: payload.configuration.cloudSources.length,
      hasTmdbKey: payload.configuration.tmdbApiKey.isNotEmpty,
      added: summary.added,
      updated: summary.updated,
      preserved: summary.preserved,
      requiresRootSelection: summary.requiresRootSelection,
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
    _phoneConnected = false;
    _completedSummary = null;
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
    _phoneConnected = false;
    _completedSummary = null;
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
