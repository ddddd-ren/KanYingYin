export 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart'
    show XunleiVerificationRequired;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kanyingyin/services/cloud/cloud_request_diagnostics.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_response_parser.dart';

typedef XunleiRequestLog = void Function(String message);

enum _XunleiRequestStage {
  coreLogin,
  captchaInit,
  signIn,
  refreshAndroid,
  refreshWeb,
  captchaInitWeb,
  account,
  listDirectory,
  fileDetail,
}

abstract interface class XunleiAuthGateway {
  String? get captchaToken;

  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  });

  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  });

  Future<XunleiAccount> account(XunleiSession session);

  Future<void> close();
}

abstract interface class XunleiApi implements XunleiAuthGateway {
  bool get hasUsableSession;

  Future<XunleiDirectoryPage> listDirectoryPage({
    required String directoryId,
    String? pageToken,
    int size = 100,
  });

  Future<XunleiFileDetail> fileDetail(String fileId);
}

class XunleiApiClient implements XunleiApi {
  XunleiApiClient({
    required String deviceId,
    String? captchaToken,
    Dio? dio,
    XunleiRequestPolicy policy = const XunleiRequestPolicy(),
    DateTime Function()? now,
    XunleiRequestLog? requestLog,
  })  : _deviceId = deviceId,
        _captchaToken = captchaToken?.trim(),
        _dio = dio ?? Dio(),
        _ownsDio = dio == null,
        _policy = policy,
        _now = now ?? DateTime.now,
        _requestLog = requestLog ?? writeCloudRequestDiagnostic,
        _parser = XunleiResponseParser(now: now ?? DateTime.now) {
    _dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..sendTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30);
  }

  final String _deviceId;
  String? _captchaToken;
  final Dio _dio;
  final bool _ownsDio;
  final XunleiRequestPolicy _policy;
  final DateTime Function() _now;
  final XunleiRequestLog _requestLog;
  final XunleiResponseParser _parser;
  XunleiSession? _session;
  XunleiClientProfile _clientProfile = XunleiClientProfile.android;

  @override
  String? get captchaToken => _captchaToken;

  @override
  bool get hasUsableSession {
    final session = _session;
    return session != null &&
        session.expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        );
  }

  @override
  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  }) async {
    _policy.requireConfigured();
    if (deviceId != _deviceId ||
        identifier.trim().isEmpty ||
        password.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    _captchaToken = captchaToken?.trim().isNotEmpty == true
        ? captchaToken!.trim()
        : _captchaToken;
    _clientProfile = XunleiClientProfile.android;
    final core = await _request(
      'POST',
      XunleiRequestPolicy.coreLoginUri,
      stage: _XunleiRequestStage.coreLogin,
      data: <String, Object?>{
        'protocolVersion': '301',
        'sequenceNo': '1000012',
        'platformVersion': '10',
        'isCompressed': '0',
        'appid': XunleiRequestPolicy.appId,
        'clientVersion': XunleiRequestPolicy.clientVersion,
        'peerID': '00000000000000000000000000000000',
        'appName': 'ANDROID-${XunleiRequestPolicy.packageName}',
        'sdkVersion': '512000',
        'devicesign': _policy.deviceSign(_deviceId),
        'netWorkType': 'WIFI',
        'providerName': 'NONE',
        'deviceModel': 'M2004J7AC',
        'deviceName': 'Xiaomi_M2004j7ac',
        'OSVersion': '12',
        'creditkey': creditKey ?? '',
        'hl': 'zh-CN',
        'userName': identifier.trim(),
        'passWord': password,
        'verifyKey': '',
        'verifyCode': '',
        'isMd5Pwd': '0',
      },
      headers: const <String, String>{
        'user-agent': 'android-ok-http-client/xl-acc-sdk/version-5.0.12.512000',
      },
    );
    final sessionId = _requiredString(core, 'sessionID');
    await _refreshCaptchaToken(identifier);
    final tokenJson = await _request(
      'POST',
      XunleiRequestPolicy.signInUri,
      stage: _XunleiRequestStage.signIn,
      data: <String, Object?>{
        'client_id': _policy.clientId,
        'client_secret': _policy.clientSecret,
        'provider': 'access_end_point_token',
        'signin_token': sessionId,
      },
    );
    return _session = _parser.parseSession(tokenJson);
  }

  @override
  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  }) async {
    _policy.requireConfigured();
    if (deviceId != _deviceId || refreshToken.trim().isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    _captchaToken = captchaToken?.trim().isNotEmpty == true
        ? captchaToken!.trim()
        : _captchaToken;
    final normalizedToken = refreshToken.trim();
    Map<String, Object?> json;
    try {
      json = await _refreshRequest(
        refreshToken: normalizedToken,
        profile: XunleiClientProfile.android,
      );
      _clientProfile = XunleiClientProfile.android;
    } on CloudDriveException catch (error) {
      if (error.type != CloudDriveErrorType.incompatible) rethrow;
      json = await _refreshRequest(
        refreshToken: normalizedToken,
        profile: XunleiClientProfile.web,
      );
      _clientProfile = XunleiClientProfile.web;
    }
    return _session = _parser.parseSession(json);
  }

  Future<Map<String, Object?>> _refreshRequest({
    required String refreshToken,
    required XunleiClientProfile profile,
  }) =>
      _request(
        'POST',
        XunleiRequestPolicy.refreshUri,
        stage: profile == XunleiClientProfile.web
            ? _XunleiRequestStage.refreshWeb
            : _XunleiRequestStage.refreshAndroid,
        profile: profile,
        headers: <String, String>{
          if (profile == XunleiClientProfile.web) 'x-action': '401',
        },
        data: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': profile == XunleiClientProfile.web
              ? _policy.webClientId
              : _policy.clientId,
          if (profile == XunleiClientProfile.android)
            'client_secret': _policy.clientSecret,
        },
      );

  @override
  Future<XunleiAccount> account(XunleiSession session) async {
    _policy.requireConfigured();
    final json = await _authorizedRequest(
      'GET',
      XunleiRequestPolicy.accountUri,
      session,
      stage: _XunleiRequestStage.account,
    );
    return _parser.parseAccount(json, fallbackUserId: session.userId);
  }

  @override
  Future<XunleiDirectoryPage> listDirectoryPage({
    required String directoryId,
    String? pageToken,
    int size = 100,
  }) async {
    _policy.requireConfigured();
    final session = _requiredSession();
    final uri = XunleiRequestPolicy.filesUri.replace(
      queryParameters: <String, String>{
        'parent_id': directoryId,
        'page_token': pageToken ?? '',
        'limit': '$size',
        '__type': 'drive',
        'refresh': 'true',
        '__sync': 'true',
        'with_audit': 'true',
        'filters':
            '{"phase":{"eq":"PHASE_TYPE_COMPLETE"},"trashed":{"eq":false}}',
      },
    );
    return _parser.parseDirectoryPage(
      await _authorizedRequest(
        'GET',
        uri,
        session,
        stage: _XunleiRequestStage.listDirectory,
      ),
    );
  }

  @override
  Future<XunleiFileDetail> fileDetail(String fileId) async {
    _policy.requireConfigured();
    final session = _requiredSession();
    final normalizedId = fileId.trim();
    if (normalizedId.isEmpty || normalizedId.contains('/')) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final uri = XunleiRequestPolicy.filesUri.replace(
      path: '${XunleiRequestPolicy.filesUri.path}/$normalizedId',
    );
    return _parser.parseFileDetail(
      await _authorizedRequest(
        'GET',
        uri,
        session,
        stage: _XunleiRequestStage.fileDetail,
      ),
    );
  }

  Future<void> _refreshCaptchaToken(String identifier) async {
    final metaKey = identifier.contains('@')
        ? 'email'
        : RegExp(r'^\d{11,18}$').hasMatch(identifier)
            ? 'phone_number'
            : 'username';
    final json = await _request(
      'POST',
      XunleiRequestPolicy.captchaInitUri,
      stage: _XunleiRequestStage.captchaInit,
      data: <String, Object?>{
        'action': 'POST:/v1/auth/signin/token',
        'captcha_token': _captchaToken ?? '',
        'client_id': _policy.clientId,
        'device_id': _deviceId,
        'meta': <String, String>{
          metaKey: identifier,
        },
        'redirect_uri': 'xlaccsdk01://xunlei.com/callback?state=kanyingyin',
      },
    );
    final verificationUrl = _optionalString(json['url']);
    if (verificationUrl != null) {
      final uri = Uri.tryParse(verificationUrl);
      if (uri == null || !_policy.isTrustedVerificationUri(uri)) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      throw XunleiVerificationRequired(
        uri: _prepareVerificationUri(uri),
        creditKey: '',
      );
    }
    final token = _requiredString(json, 'captcha_token');
    _captchaToken = token;
  }

  Future<Map<String, Object?>> _authorizedRequest(
    String method,
    Uri uri,
    XunleiSession session, {
    required _XunleiRequestStage stage,
  }) async {
    final profile = _clientProfile;
    if (profile == XunleiClientProfile.web &&
        _captchaToken?.isNotEmpty != true) {
      await _refreshAuthorizedCaptchaToken(
        method: method,
        uri: uri,
        profile: profile,
      );
    }

    Future<Map<String, Object?>> send() => _request(
          method,
          uri,
          stage: stage,
          headers: <String, String>{
            'Authorization': session.authorization,
            if (_captchaToken?.isNotEmpty == true)
              'X-Captcha-Token': _captchaToken!,
          },
        );

    try {
      return await send();
    } on CloudDriveException catch (error) {
      if (error.type != CloudDriveErrorType.verificationRequired) {
        rethrow;
      }
      await _refreshAuthorizedCaptchaToken(
        method: method,
        uri: uri,
        profile: profile,
      );
      return send();
    }
  }

  Future<void> _refreshAuthorizedCaptchaToken({
    required String method,
    required Uri uri,
    required XunleiClientProfile profile,
  }) async {
    final meta = switch (profile) {
      XunleiClientProfile.android => _authorizedAndroidCaptchaMeta(),
      XunleiClientProfile.web => const <String, String>{
          'username': '',
          'phone_number': '',
          'email': '',
        },
    };
    final json = await _request(
      'POST',
      XunleiRequestPolicy.captchaInitUri,
      stage: profile == XunleiClientProfile.web
          ? _XunleiRequestStage.captchaInitWeb
          : _XunleiRequestStage.captchaInit,
      profile: profile,
      data: <String, Object?>{
        'client_id': profile == XunleiClientProfile.web
            ? _policy.webClientId
            : _policy.clientId,
        'action': '${method.toUpperCase()}:${uri.path}',
        'device_id': _deviceId,
        'captcha_token': _captchaToken ?? '',
        'meta': meta,
      },
    );
    _captchaToken = _requiredString(json, 'captcha_token');
  }

  Map<String, String> _authorizedAndroidCaptchaMeta() {
    final timestamp = '${_now().millisecondsSinceEpoch}';
    return <String, String>{
      'client_version': XunleiRequestPolicy.clientVersion,
      'package_name': XunleiRequestPolicy.packageName,
      'user_id': _requiredSession().userId,
      'timestamp': timestamp,
      'captcha_sign': _policy.captchaSign(
        deviceId: _deviceId,
        timestamp: timestamp,
      ),
    };
  }

  Future<Map<String, Object?>> _request(
    String method,
    Uri uri, {
    required _XunleiRequestStage stage,
    Object? data,
    Map<String, String> headers = const <String, String>{},
    XunleiClientProfile? profile,
  }) async {
    var statusCode = 0;
    _requestLog('迅雷请求 stage=${stage.name} started');
    try {
      final response = await _dio.requestUri<Object?>(
        uri,
        data: data,
        options: Options(
          method: method,
          headers: <String, String>{
            ..._policy.apiHeaders(
              deviceId: _deviceId,
              profile: profile ?? _clientProfile,
            ),
            ...headers,
          },
          validateStatus: (_) => true,
        ),
      );
      statusCode = response.statusCode ?? 0;
      final json = _asMap(response.data);
      if (_optionalString(json['error']) == 'review_panel') {
        final challenge = _parser.parseVerificationRequired(json);
        if (!_policy.isTrustedVerificationUri(challenge.uri)) {
          throw const CloudDriveException(CloudDriveErrorType.incompatible);
        }
        _requestLog(
          '迅雷请求 stage=${stage.name} status=$statusCode '
          'error=${CloudDriveErrorType.verificationRequired.name}',
        );
        throw XunleiVerificationRequired(
          uri: _prepareVerificationUri(challenge.uri),
          creditKey: challenge.creditKey,
        );
      }
      if (statusCode < 200 || statusCode >= 300 || _hasApiError(json)) {
        throw CloudDriveException(_errorType(stage, statusCode, json));
      }
      _requestLog(
        '迅雷请求 stage=${stage.name} status=$statusCode success',
      );
      return json;
    } on XunleiVerificationRequired {
      rethrow;
    } on CloudDriveException catch (error) {
      _requestLog(
        '迅雷请求 stage=${stage.name} status=$statusCode '
        'error=${error.type.name}',
      );
      rethrow;
    } on DioException catch (error) {
      final errorType = error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout
          ? CloudDriveErrorType.timeout
          : CloudDriveErrorType.network;
      _requestLog(
        '迅雷请求 stage=${stage.name} status=0 error=${errorType.name}',
      );
      throw CloudDriveException(errorType);
    } on Object {
      _requestLog(
        '迅雷请求 stage=${stage.name} status=$statusCode '
        'error=${CloudDriveErrorType.incompatible.name}',
      );
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  Map<String, Object?> _asMap(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return Map<String, Object?>.from(decoded);
  }

  bool _hasApiError(Map<String, Object?> json) {
    final code = json['error_code'];
    final numericCode = code is num ? code.toInt() : int.tryParse('$code');
    final error = _optionalString(json['error']);
    return (numericCode != null && numericCode != 0) ||
        (error != null && error != 'success');
  }

  CloudDriveErrorType _errorType(
    _XunleiRequestStage stage,
    int? statusCode,
    Map<String, Object?> json,
  ) {
    final error = _optionalString(json['error'])?.toLowerCase();
    final description =
        _optionalString(json['error_description'])?.toLowerCase();
    final code = json['error_code'];
    final numericCode = code is num ? code.toInt() : int.tryParse('$code');
    if (error == 'invalid_argument' &&
        description?.contains('invalid captcha_sign') == true) {
      return CloudDriveErrorType.protocolUpdated;
    }
    if (stage == _XunleiRequestStage.coreLogin &&
        _isExplicitPasswordError(error, description)) {
      return CloudDriveErrorType.invalidPassword;
    }
    if ((stage == _XunleiRequestStage.refreshAndroid ||
            stage == _XunleiRequestStage.refreshWeb) &&
        statusCode == 400 &&
        (error == 'invalid_argument' || numericCode == 3)) {
      return CloudDriveErrorType.authentication;
    }
    if (error == 'captcha_required' || error == 'captcha_invalid') {
      return CloudDriveErrorType.verificationRequired;
    }
    if (statusCode == 401 || statusCode == 403) {
      return CloudDriveErrorType.authentication;
    }
    if (statusCode == 404) return CloudDriveErrorType.notFound;
    if (statusCode == 429) return CloudDriveErrorType.rateLimited;
    if (statusCode != null && statusCode >= 500) {
      return CloudDriveErrorType.network;
    }
    return switch (numericCode) {
      9 => CloudDriveErrorType.verificationRequired,
      10 || 16 || 4121 || 4122 => CloudDriveErrorType.authentication,
      _ => CloudDriveErrorType.incompatible,
    };
  }

  bool _isExplicitPasswordError(String? error, String? description) {
    if (const <String>{
      'invalid_password',
      'password_error',
      'wrong_password',
    }.contains(error)) {
      return true;
    }
    final text = description ?? '';
    return text.contains('密码错误') ||
        text.contains('密码不正确') ||
        text.contains('密码有误') ||
        (text.contains('password') &&
            (text.contains('incorrect') ||
                text.contains('invalid') ||
                text.contains('wrong')));
  }

  XunleiSession _requiredSession() {
    final session = _session;
    if (session == null) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    return session;
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = _optionalString(json[key]);
    if (value == null) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return value;
  }

  String? _optionalString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Uri _prepareVerificationUri(Uri uri) {
    final path = uri.path == '/xlcaptcha/verifyPhone.html'
        ? '/xlcaptcha/vertifyPhone.html'
        : uri.path;
    return uri.replace(
      path: path,
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'deviceid': _policy.deviceSign(_deviceId),
      },
    );
  }

  @override
  Future<void> close() async {
    _session = null;
    _captchaToken = null;
    _clientProfile = XunleiClientProfile.android;
    if (_ownsDio) _dio.close(force: true);
  }

  @override
  String toString() => 'XunleiApiClient(<redacted>)';
}
