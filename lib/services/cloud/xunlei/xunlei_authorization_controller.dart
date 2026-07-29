import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

enum XunleiAuthorizationState {
  idle,
  signingIn,
  verificationRequired,
  verifying,
  authorized,
  failed,
}

typedef XunleiGatewayFactory = XunleiAuthGateway Function(String deviceId);

class XunleiAuthorizationController extends ChangeNotifier {
  XunleiAuthorizationController({
    XunleiAuthGateway? gateway,
    XunleiGatewayFactory? gatewayFactory,
    DateTime Function()? now,
    String Function()? deviceIdGenerator,
    XunleiRequestPolicy policy = const XunleiRequestPolicy(),
  })  : _gateway = gateway,
        _gatewayFactory = gatewayFactory ?? _createGateway,
        _now = now ?? DateTime.now,
        _deviceIdGenerator = deviceIdGenerator ?? _generateDeviceId,
        _policy = policy;

  static const Duration _verificationLifetime = Duration(minutes: 10);

  XunleiAuthGateway? _gateway;
  String? _gatewayDeviceId;
  final XunleiGatewayFactory _gatewayFactory;
  final DateTime Function() _now;
  final String Function() _deviceIdGenerator;
  final XunleiRequestPolicy _policy;

  XunleiAuthorizationState _state = XunleiAuthorizationState.idle;
  CloudCredential? _authorizedCredential;
  Uri? _verificationUri;
  String? _errorMessage;
  String? _pendingIdentifier;
  String? _pendingPassword;
  String? _pendingDeviceId;
  String? _pendingCreditKey;
  DateTime? _verificationStartedAt;
  bool _disposed = false;

  XunleiAuthorizationState get state => _state;
  CloudCredential? get authorizedCredential => _authorizedCredential;
  Uri? get verificationUri => _verificationUri;
  String? get errorMessage => _errorMessage;

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final normalizedIdentifier = identifier.trim();
    if (normalizedIdentifier.isEmpty || password.isEmpty) {
      _fail('请填写迅雷账号和密码');
    }
    _clearPendingSecrets();
    final deviceId = _deviceIdGenerator();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(deviceId)) {
      _fail('无法创建安全设备标识');
    }
    _pendingIdentifier = normalizedIdentifier;
    _pendingPassword = password;
    _pendingDeviceId = deviceId;
    _state = XunleiAuthorizationState.signingIn;
    _errorMessage = null;
    _notify();
    await _authorize(creditKey: null);
  }

  Future<void> authorizeWithRefreshToken({
    required String refreshToken,
    String? deviceId,
  }) async {
    final normalizedToken = refreshToken.trim();
    if (normalizedToken.isEmpty) {
      _fail('请填写 Refresh Token');
    }
    final normalizedDeviceId = deviceId?.trim();
    final resolvedDeviceId = normalizedDeviceId?.isNotEmpty == true
        ? normalizedDeviceId!
        : _deviceIdGenerator();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(resolvedDeviceId)) {
      _fail('设备标识无效，请重新授权');
    }

    _clearPendingSecrets();
    _state = XunleiAuthorizationState.signingIn;
    _errorMessage = null;
    _notify();
    try {
      final gateway = await _gatewayForDevice(resolvedDeviceId);
      final session = await gateway.refresh(
        refreshToken: normalizedToken,
        deviceId: resolvedDeviceId,
        captchaToken: gateway.captchaToken,
      );
      final account = await gateway.account(session);
      _authorizedCredential = CloudCredential(
        refreshToken: session.refreshToken,
        deviceId: resolvedDeviceId,
        captchaToken: gateway.captchaToken,
        userId: account.userId,
        accountLabel: account.accountLabel,
      );
      _state = XunleiAuthorizationState.authorized;
      _errorMessage = null;
      _notify();
    } on CloudDriveException catch (error) {
      _state = XunleiAuthorizationState.failed;
      _errorMessage = _messageForRefresh(error.type);
      _notify();
      rethrow;
    } on Object {
      _state = XunleiAuthorizationState.failed;
      _errorMessage = '迅雷授权失败，请稍后重试';
      _notify();
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  Future<void> completeVerification() async {
    final startedAt = _verificationStartedAt;
    if (_state != XunleiAuthorizationState.verificationRequired ||
        startedAt == null ||
        _pendingIdentifier == null ||
        _pendingPassword == null ||
        _pendingDeviceId == null) {
      _fail('没有可继续的迅雷验证');
    }
    if (_now().toUtc().difference(startedAt) > _verificationLifetime) {
      _clearPendingSecrets();
      _state = XunleiAuthorizationState.failed;
      _errorMessage = '迅雷验证已过期，请重新登录';
      _notify();
      throw const CloudDriveException(
        CloudDriveErrorType.verificationRequired,
      );
    }
    _state = XunleiAuthorizationState.verifying;
    _errorMessage = null;
    _notify();
    await _authorize(creditKey: _pendingCreditKey);
  }

  Future<void> _authorize({required String? creditKey}) async {
    final identifier = _pendingIdentifier!;
    final password = _pendingPassword!;
    final deviceId = _pendingDeviceId!;
    try {
      final gateway = await _gatewayForDevice(deviceId);
      final session = await gateway.login(
        identifier: identifier,
        password: password,
        deviceId: deviceId,
        captchaToken: gateway.captchaToken,
        creditKey: creditKey,
      );
      final account = await gateway.account(session);
      _authorizedCredential = CloudCredential(
        refreshToken: session.refreshToken,
        deviceId: deviceId,
        captchaToken: gateway.captchaToken,
        userId: account.userId,
        accountLabel: account.accountLabel,
      );
      _clearPendingSecrets();
      _state = XunleiAuthorizationState.authorized;
      _errorMessage = null;
      _notify();
    } on XunleiVerificationRequired catch (challenge) {
      if (!_policy.isTrustedVerificationUri(challenge.uri)) {
        _clearPendingSecrets();
        _state = XunleiAuthorizationState.failed;
        _errorMessage = '迅雷返回了不受信任的验证地址';
        _notify();
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      _verificationUri = challenge.uri;
      _pendingCreditKey = challenge.creditKey;
      _verificationStartedAt = _now().toUtc();
      _state = XunleiAuthorizationState.verificationRequired;
      _errorMessage = null;
      _notify();
      rethrow;
    } on CloudDriveException catch (error) {
      _clearPendingSecrets();
      _state = XunleiAuthorizationState.failed;
      _errorMessage = _messageFor(error.type);
      _notify();
      rethrow;
    } on Object {
      _clearPendingSecrets();
      _state = XunleiAuthorizationState.failed;
      _errorMessage = '迅雷登录失败，请稍后重试';
      _notify();
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  void cancelVerification() {
    _clearPendingSecrets();
    _state = XunleiAuthorizationState.idle;
    _errorMessage = null;
    _notify();
  }

  Future<XunleiAuthGateway> _gatewayForDevice(String deviceId) async {
    final current = _gateway;
    if (current != null &&
        (_gatewayDeviceId == null || _gatewayDeviceId == deviceId)) {
      _gatewayDeviceId ??= deviceId;
      return current;
    }
    if (current != null) await current.close();
    final replacement = _gatewayFactory(deviceId);
    _gateway = replacement;
    _gatewayDeviceId = deviceId;
    return replacement;
  }

  Never _fail(String message) {
    _clearPendingSecrets();
    _state = XunleiAuthorizationState.failed;
    _errorMessage = message;
    _notify();
    throw const CloudDriveException(CloudDriveErrorType.authentication);
  }

  void _clearPendingSecrets() {
    _pendingIdentifier = null;
    _pendingPassword = null;
    _pendingDeviceId = null;
    _pendingCreditKey = null;
    _verificationUri = null;
    _verificationStartedAt = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _messageFor(CloudDriveErrorType type) => switch (type) {
        CloudDriveErrorType.authentication => '迅雷账号登录失败，请检查账号或重新登录',
        CloudDriveErrorType.verificationRequired => '迅雷需要完成设备验证',
        CloudDriveErrorType.network => '网络连接失败，请检查网络后重试',
        CloudDriveErrorType.timeout => '迅雷登录请求超时，请稍后重试',
        CloudDriveErrorType.rateLimited => '迅雷请求过于频繁，请稍后再试',
        CloudDriveErrorType.protocolUpdated => '迅雷登录协议已更新，请改用 Refresh Token',
        _ => '迅雷登录失败，请稍后重试',
      };

  static String _messageForRefresh(CloudDriveErrorType type) => switch (type) {
        CloudDriveErrorType.authentication => 'Refresh Token 无效或已过期，请重新填写',
        CloudDriveErrorType.network => '网络连接失败，请检查网络后重试',
        CloudDriveErrorType.timeout => '迅雷授权请求超时，请稍后重试',
        CloudDriveErrorType.rateLimited => '迅雷请求过于频繁，请稍后再试',
        CloudDriveErrorType.protocolUpdated => '迅雷登录协议已更新，请重新获取 Refresh Token',
        _ => '迅雷授权失败，请稍后重试',
      };

  static XunleiAuthGateway _createGateway(String deviceId) =>
      XunleiApiClient(deviceId: deviceId);

  static String _generateDeviceId() {
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearPendingSecrets();
    final gateway = _gateway;
    _gateway = null;
    _gatewayDeviceId = null;
    if (gateway != null) unawaited(gateway.close());
    super.dispose();
  }

  @override
  String toString() =>
      'XunleiAuthorizationController(state: ${_state.name}, <redacted>)';
}
