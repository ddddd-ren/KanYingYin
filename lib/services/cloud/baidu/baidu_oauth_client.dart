import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';

class BaiduOAuthClient {
  BaiduOAuthClient({
    required this.clientId,
    required this.clientSecret,
    Dio? dio,
    DateTime Function()? now,
  })  : _dio = dio ?? Dio(),
        _now = now ?? DateTime.now;

  static final Uri _authorizationEndpoint =
      Uri.https('openapi.baidu.com', '/oauth/2.0/authorize');
  static final Uri _tokenEndpoint =
      Uri.https('openapi.baidu.com', '/oauth/2.0/token');

  final String clientId;
  final String clientSecret;
  final Dio _dio;
  final DateTime Function() _now;
  Future<BaiduOAuthTokens>? _refreshing;

  Uri buildAuthorizationUri({required String state}) =>
      _authorizationEndpoint.replace(queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': 'oob',
        'scope': 'basic,netdisk',
        'state': state,
      });

  Future<BaiduOAuthTokens> exchangeCode(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    return _requestTokens(<String, String>{
      'grant_type': 'authorization_code',
      'code': normalized,
      'client_id': clientId,
      'client_secret': clientSecret,
      'redirect_uri': 'oob',
    });
  }

  Future<BaiduOAuthTokens> refresh(String refreshToken) {
    final existing = _refreshing;
    if (existing != null) return existing;
    final normalized = refreshToken.trim();
    if (normalized.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    late final Future<BaiduOAuthTokens> task;
    task = _requestTokens(<String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': normalized,
      'client_id': clientId,
      'client_secret': clientSecret,
    }).whenComplete(() {
      if (identical(_refreshing, task)) _refreshing = null;
    });
    _refreshing = task;
    return task;
  }

  Future<BaiduOAuthTokens> _requestTokens(
    Map<String, String> queryParameters,
  ) async {
    try {
      final response = await _dio.get<Object?>(
        _tokenEndpoint.toString(),
        queryParameters: queryParameters,
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return _parseTokens(response.data);
    } on CloudDriveException {
      rethrow;
    } on DioException catch (error) {
      throw CloudDriveException(_mapDioError(error));
    } on Object {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  BaiduOAuthTokens _parseTokens(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map<Object?, Object?>) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final json = Map<String, Object?>.from(decoded);
    final accessToken = json['access_token'];
    final refreshToken = json['refresh_token'];
    final expiresIn = json['expires_in'];
    final scope = json['scope'];
    if (accessToken is! String ||
        accessToken.trim().isEmpty ||
        refreshToken is! String ||
        refreshToken.trim().isEmpty ||
        expiresIn is! num ||
        expiresIn.toInt() <= 0 ||
        scope is! String) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final scopes = scope
        .split(RegExp(r'[\s,]+'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (!scopes.contains('netdisk')) {
      throw const CloudDriveException(CloudDriveErrorType.permission);
    }
    return BaiduOAuthTokens(
      accessToken: accessToken.trim(),
      refreshToken: refreshToken.trim(),
      expiresAt: _now().toUtc().add(Duration(seconds: expiresIn.toInt())),
      scopes: scopes,
    );
  }

  CloudDriveErrorType _mapDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 429) return CloudDriveErrorType.rateLimited;
    if (statusCode == 400 || statusCode == 401 || statusCode == 403) {
      return CloudDriveErrorType.authentication;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return CloudDriveErrorType.timeout;
    }
    if (error.type == DioExceptionType.connectionError) {
      return CloudDriveErrorType.network;
    }
    return CloudDriveErrorType.incompatible;
  }
}
