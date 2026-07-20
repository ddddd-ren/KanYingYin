import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_api_client.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_oauth_client.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';

typedef BaiduOAuthFactory = BaiduOAuthGateway Function({
  required String clientId,
  required String clientSecret,
});

typedef BaiduAccountLoader = Future<BaiduAccount> Function(String accessToken);

class BaiduAuthorizationController extends ChangeNotifier {
  BaiduAuthorizationController({
    BaiduOAuthFactory? oauthFactory,
    BaiduAccountLoader? accountLoader,
    DateTime Function()? now,
    String Function()? stateGenerator,
  })  : _oauthFactory = oauthFactory ?? _createOAuthGateway,
        _accountLoader = accountLoader ?? _loadAccount,
        _now = now ?? DateTime.now,
        _stateGenerator = stateGenerator ?? _generateState;

  static const Duration _sessionLifetime = Duration(minutes: 10);

  final BaiduOAuthFactory _oauthFactory;
  final BaiduAccountLoader _accountLoader;
  final DateTime Function() _now;
  final String Function() _stateGenerator;

  Uri? _authorizationUri;
  bool _authorizing = false;
  BaiduAccount? _account;
  CloudCredential? _authorizedCredential;
  String? _errorMessage;
  BaiduOAuthGateway? _gateway;
  DateTime? _sessionStartedAt;
  String? _clientId;
  String? _clientSecret;
  bool _codeConsumed = false;

  Uri? get authorizationUri => _authorizationUri;
  bool get authorizing => _authorizing;
  BaiduAccount? get account => _account;
  CloudCredential? get authorizedCredential => _authorizedCredential;
  String? get errorMessage => _errorMessage;

  Uri begin({required String clientId, required String clientSecret}) {
    final normalizedClientId = clientId.trim();
    final normalizedClientSecret = clientSecret.trim();
    if (normalizedClientId.isEmpty || normalizedClientSecret.isEmpty) {
      _errorMessage = '请先填写 API Key 和 Secret Key';
      notifyListeners();
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    final state = _stateGenerator().trim();
    if (state.isEmpty) {
      _errorMessage = '无法创建安全授权会话';
      notifyListeners();
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final gateway = _oauthFactory(
      clientId: normalizedClientId,
      clientSecret: normalizedClientSecret,
    );
    final uri = gateway.buildAuthorizationUri(state: state);
    _gateway = gateway;
    _clientId = normalizedClientId;
    _clientSecret = normalizedClientSecret;
    _sessionStartedAt = _now().toUtc();
    _codeConsumed = false;
    _authorizationUri = uri;
    _authorizing = false;
    _account = null;
    _authorizedCredential = null;
    _errorMessage = null;
    notifyListeners();
    return uri;
  }

  Future<void> exchangeCode(String code) async {
    final gateway = _gateway;
    final startedAt = _sessionStartedAt;
    final clientId = _clientId;
    final clientSecret = _clientSecret;
    if (gateway == null ||
        startedAt == null ||
        clientId == null ||
        clientSecret == null) {
      _reject('请先打开百度授权页面');
    }
    if (_now().toUtc().difference(startedAt) > _sessionLifetime) {
      _reject('授权会话已过期，请重新打开百度授权');
    }
    if (_codeConsumed) {
      _reject('授权码已使用，请重新打开百度授权');
    }
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty ||
        normalizedCode.length > 2048 ||
        normalizedCode.contains(RegExp(r'\s'))) {
      _reject('请粘贴有效的百度授权码');
    }

    _codeConsumed = true;
    _authorizing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final tokens = await gateway.exchangeCode(normalizedCode);
      final verifiedAccount = await _accountLoader(tokens.accessToken);
      _account = verifiedAccount;
      _authorizedCredential = CloudCredential(
        clientId: clientId,
        clientSecret: clientSecret,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessTokenExpiresAt: tokens.expiresAt.toUtc(),
      );
    } on CloudDriveException catch (error) {
      _errorMessage = _messageFor(error.type);
      rethrow;
    } on Object {
      _errorMessage = '百度授权失败，请稍后重试';
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    } finally {
      _authorizing = false;
      notifyListeners();
    }
  }

  Never _reject(String message) {
    _errorMessage = message;
    notifyListeners();
    throw const CloudDriveException(CloudDriveErrorType.authentication);
  }

  void cancel() {
    _gateway = null;
    _clientId = null;
    _clientSecret = null;
    _sessionStartedAt = null;
    _codeConsumed = false;
    _authorizationUri = null;
    _authorizing = false;
    _account = null;
    _authorizedCredential = null;
    _errorMessage = null;
    notifyListeners();
  }

  static String _messageFor(CloudDriveErrorType type) => switch (type) {
        CloudDriveErrorType.authentication => '百度授权码无效或已过期，请重新授权',
        CloudDriveErrorType.permission => '百度授权缺少网盘权限，请重新授权',
        CloudDriveErrorType.network => '网络连接失败，请检查网络后重试',
        CloudDriveErrorType.timeout => '百度授权请求超时，请稍后重试',
        CloudDriveErrorType.rateLimited => '百度请求过于频繁，请稍后重试',
        _ => '百度授权失败，请稍后重试',
      };

  static BaiduOAuthGateway _createOAuthGateway({
    required String clientId,
    required String clientSecret,
  }) =>
      BaiduOAuthClient(clientId: clientId, clientSecret: clientSecret);

  static Future<BaiduAccount> _loadAccount(String accessToken) async {
    final api = BaiduApiClient(accessToken: accessToken);
    try {
      return await api.account();
    } finally {
      await api.close();
    }
  }

  static String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
