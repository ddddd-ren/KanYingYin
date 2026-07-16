import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_models.dart';

class OpenListClient implements CloudDriveClient {
  OpenListClient({
    required CloudSource source,
    required CloudCredentialStore credentialStore,
    Dio? dio,
    bool allowSelfSignedCertificate = false,
  })  : _source = source,
        _credentialStore = credentialStore,
        _dio = dio ?? Dio() {
    _dio.options.baseUrl = normalizeBaseUrl(source.baseUrl);
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    if (dio == null && allowSelfSignedCertificate) {
      final adapter = IOHttpClientAdapter();
      adapter.createHttpClient =
          () => HttpClient()..badCertificateCallback = (_, __, ___) => true;
      _dio.httpClientAdapter = adapter;
    }
  }

  final CloudSource _source;
  final CloudCredentialStore _credentialStore;
  final Dio _dio;

  static String normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.invalidAddress);
    }
    return normalized;
  }

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) =>
      ensureAuthenticated(credential: credential);

  Future<void> ensureAuthenticated({CloudCredential? credential}) async {
    if (credential != null) {
      await _credentialStore.write(_source.id, credential);
    }
    final current = await _credentialStore.read(_source.id);
    if (current?.token?.isNotEmpty ?? false) return;
    if (!_hasAccountCredential(current)) return;
    await _login(current!);
  }

  Future<void> _login(CloudCredential credential) async {
    try {
      final response = await _dio.post<Object?>(
        '/api/auth/login',
        data: <String, Object?>{
          'username': credential.username ?? '',
          'password': credential.password ?? '',
        },
      );
      final data = _responseData(response.data, authenticationRequest: true);
      final token = data['token'];
      if (token is! String || token.isEmpty) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      await _credentialStore.write(
        _source.id,
        CloudCredential(
          username: credential.username,
          password: credential.password,
          cookie: credential.cookie,
          token: token,
        ),
      );
    } on CloudDriveException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioError(error, authenticationRequest: true);
    } on FormatException {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  @override
  Future<List<CloudFileEntry>> listDirectory(
    String remotePath, {
    String password = '',
  }) async {
    const perPage = 100;
    var page = 1;
    final result = <CloudFileEntry>[];
    while (true) {
      final data = await _post(
        '/api/fs/list',
        <String, Object?>{
          'path': remotePath,
          'password': password,
          'page': page,
          'per_page': perPage,
          'refresh': false,
        },
      );
      OpenListListPage parsed;
      try {
        parsed = OpenListListPage.fromJson(data, parentPath: remotePath);
      } on FormatException {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      result.addAll(parsed.files.map((file) => file.entry));
      if (result.length >= parsed.total || parsed.files.isEmpty) break;
      page++;
    }
    return result;
  }

  Future<OpenListFile> _fetchFile(String remotePath) async {
    final data = await _post(
      '/api/fs/get',
      <String, Object?>{'path': remotePath, 'password': ''},
    );
    try {
      final file = OpenListFile.fromJson(data, remotePath: remotePath);
      if (file.entry.name.isEmpty || file.entry.remotePath.isEmpty) {
        throw const FormatException();
      }
      return file;
    } on FormatException {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  @override
  Future<CloudFileEntry> getFile(String remotePath) async =>
      (await _fetchFile(remotePath)).entry;

  @override
  Future<CloudPlaybackResource> resolvePlayback(String remotePath) async {
    final file = await _fetchFile(remotePath);
    if (file.rawUrl == null) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return CloudPlaybackResource(uri: file.rawUrl!, headers: file.headers);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    await ensureAuthenticated();
    var credential = await _credentialStore.read(_source.id);
    try {
      return await _postOnce(path, body, credential?.token);
    } on CloudDriveException catch (error) {
      final canRefresh = error.type == CloudDriveErrorType.authentication &&
          _hasAccountCredential(credential);
      if (!canRefresh) rethrow;
      await _login(credential!);
      credential = await _credentialStore.read(_source.id);
      return _postOnce(path, body, credential?.token);
    }
  }

  static bool _hasAccountCredential(CloudCredential? credential) =>
      (credential?.username?.isNotEmpty ?? false) &&
      (credential?.password?.isNotEmpty ?? false);

  Future<Map<String, dynamic>> _postOnce(
    String path,
    Map<String, Object?> body,
    String? token,
  ) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: body,
        options: Options(headers: <String, Object?>{
          if (token?.isNotEmpty ?? false) 'Authorization': token,
        }),
      );
      return _responseData(response.data);
    } on CloudDriveException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on FormatException {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
  }

  static Map<String, dynamic> _responseData(
    Object? value, {
    bool authenticationRequest = false,
  }) {
    if (value is! Map) throw const FormatException();
    final response = Map<String, dynamic>.from(value);
    final code = response['code'];
    if (code is num && code.toInt() != 200) {
      throw CloudDriveException(
        _mapStatus(
          code.toInt(),
          authenticationRequest: authenticationRequest,
        ),
      );
    }
    final data = response['data'];
    if (data is! Map) throw const FormatException();
    return Map<String, dynamic>.from(data);
  }

  static CloudDriveException _mapDioError(
    DioException error, {
    bool authenticationRequest = false,
  }) {
    final cause = error.error;
    if (error.type == DioExceptionType.badCertificate ||
        cause is HandshakeException ||
        cause.toString().toLowerCase().contains('certificate')) {
      return const CloudDriveException(CloudDriveErrorType.certificate);
    }
    if (cause is FormatException || cause is ArgumentError) {
      return const CloudDriveException(CloudDriveErrorType.invalidAddress);
    }
    final status = error.response?.statusCode;
    if (status != null) {
      return CloudDriveException(
        _mapStatus(
          status,
          authenticationRequest: authenticationRequest,
        ),
      );
    }
    return const CloudDriveException(CloudDriveErrorType.network);
  }

  static CloudDriveErrorType _mapStatus(
    int status, {
    bool authenticationRequest = false,
  }) =>
      switch (status) {
        400 when authenticationRequest => CloudDriveErrorType.authentication,
        401 => CloudDriveErrorType.authentication,
        403 => CloudDriveErrorType.permission,
        404 => CloudDriveErrorType.notFound,
        _ => CloudDriveErrorType.incompatible,
      };

  @override
  Future<void> close() async => _dio.close(force: true);

  @override
  String toString() => 'OpenListClient(sourceId: ${_source.id})';
}
