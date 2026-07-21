import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_drive_client.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';

typedef CloudProviderClientFactory = CloudDriveClient Function(
  CloudSource source,
  CloudCredentialStore credentialStore,
  bool allowSelfSignedCertificate,
);

typedef CloudProviderRangeReaderFactory = CloudRangeRemoteReader Function({
  required CloudSource source,
  required CloudPlaybackResource resource,
  required Future<CloudPlaybackResource> Function() refreshResource,
  required CloudCredentialStore credentialStore,
});

class CloudProviderRegistry {
  CloudProviderRegistry({
    Map<CloudSourceType, CloudProviderClientFactory> clientFactories =
        const <CloudSourceType, CloudProviderClientFactory>{},
    Map<CloudSourceType, CloudProviderRangeReaderFactory> rangeReaderFactories =
        const <CloudSourceType, CloudProviderRangeReaderFactory>{},
  })  : _clientFactories = <CloudSourceType, CloudProviderClientFactory>{
          CloudSourceType.openList: _createOpenListClient,
          CloudSourceType.quark: _createQuarkClient,
          CloudSourceType.baidu: _createBaiduClient,
          ...clientFactories,
        },
        _rangeReaderFactories =
            <CloudSourceType, CloudProviderRangeReaderFactory>{
          CloudSourceType.quark: _createQuarkRangeReader,
          CloudSourceType.baidu: _createBaiduRangeReader,
          ...rangeReaderFactories,
        };

  final Map<CloudSourceType, CloudProviderClientFactory> _clientFactories;
  final Map<CloudSourceType, CloudProviderRangeReaderFactory>
      _rangeReaderFactories;

  CloudDriveClient createClient(
    CloudSource source,
    CloudCredentialStore credentialStore,
  ) {
    final factory = _clientFactories[source.type];
    if (factory == null) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return factory(
      source,
      credentialStore,
      supportsSelfSignedCertificate(source.type) &&
          source.allowSelfSignedCertificate,
    );
  }

  CloudRangeRemoteReader createRangeReader({
    required CloudSource source,
    required CloudPlaybackResource resource,
    required Future<CloudPlaybackResource> Function() refreshResource,
    required CloudCredentialStore credentialStore,
  }) {
    final factory = _rangeReaderFactories[source.type];
    if (factory == null) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return factory(
      source: source,
      resource: resource,
      refreshResource: refreshResource,
      credentialStore: credentialStore,
    );
  }

  String providerName(CloudSourceType type) => switch (type) {
        CloudSourceType.openList => 'OpenList',
        CloudSourceType.quark => '夸克网盘',
        CloudSourceType.baidu => '百度网盘',
      };

  bool supportsSelfSignedCertificate(CloudSourceType type) =>
      type == CloudSourceType.openList;

  bool supportsShareTransfer(CloudSourceType type) =>
      type == CloudSourceType.quark;

  CloudSource normalizeSource(CloudSource source) => switch (source.type) {
        CloudSourceType.openList => source.copyWith(
            baseUrl: OpenListClient.normalizeBaseUrl(source.baseUrl),
          ),
        CloudSourceType.quark => source.copyWith(
            baseUrl: 'https://pan.quark.cn',
            allowSelfSignedCertificate: false,
          ),
        CloudSourceType.baidu => source.copyWith(
            baseUrl: 'https://pan.baidu.com',
            allowSelfSignedCertificate: false,
          ),
      };

  String? normalizeEndpoint(CloudSource source) {
    try {
      return normalizeSource(source).baseUrl;
    } on CloudDriveException {
      return null;
    }
  }

  CloudCredential mergeCredential({
    required CloudSource source,
    required CloudCredential form,
    required CloudCredential? existing,
    required bool endpointUnchanged,
  }) =>
      switch (source.type) {
        CloudSourceType.openList => _mergeOpenListCredential(
            form: form,
            existing: existing,
            endpointUnchanged: endpointUnchanged,
          ),
        CloudSourceType.quark => _mergeQuarkCredential(
            form: form,
            existing: existing,
          ),
        CloudSourceType.baidu => _mergeBaiduCredential(
            form: form,
            existing: existing,
          ),
      };

  String errorMessage(
    CloudSourceType type,
    CloudDriveException error,
  ) =>
      switch ((type, error.type)) {
        (CloudSourceType.openList, CloudDriveErrorType.authentication) =>
          '用户名或密码错误',
        (CloudSourceType.quark, CloudDriveErrorType.authentication) =>
          '夸克 Cookie 无效或已失效',
        (CloudSourceType.baidu, CloudDriveErrorType.authentication) =>
          '百度网盘授权无效或已失效',
        (_, CloudDriveErrorType.permission) => '当前账号没有访问权限',
        (_, CloudDriveErrorType.network) => '连接失败，请检查网络',
        (CloudSourceType.openList, CloudDriveErrorType.notFound) =>
          '未找到 OpenList 服务',
        (CloudSourceType.quark, CloudDriveErrorType.notFound) => '夸克目录或文件不存在',
        (CloudSourceType.baidu, CloudDriveErrorType.notFound) => '百度目录或文件不存在',
        (_, CloudDriveErrorType.certificate) => '服务器证书不受信任',
        (_, CloudDriveErrorType.invalidAddress) => '服务器地址格式无效',
        (_, CloudDriveErrorType.timeout) => '网络请求超时',
        (_, CloudDriveErrorType.rateLimited) => '请求过于频繁，请稍后再试',
        (_, CloudDriveErrorType.shareExpired) => '夸克分享已失效',
        (_, CloudDriveErrorType.invalidPasscode) => '夸克分享提取码错误',
        (_, CloudDriveErrorType.insufficientSpace) => '夸克网盘空间不足',
        (_, CloudDriveErrorType.taskFailed) => '夸克转存任务失败',
        (_, CloudDriveErrorType.taskTimeout) => '夸克转存任务超时',
        (_, CloudDriveErrorType.cancelled) => '操作已取消',
        (CloudSourceType.quark, CloudDriveErrorType.incompatible) =>
          '当前版本暂不兼容夸克接口',
        (CloudSourceType.baidu, CloudDriveErrorType.incompatible) =>
          '当前版本暂不兼容百度网盘接口',
        _ => '服务响应不兼容',
      };

  static CloudCredential _mergeOpenListCredential({
    required CloudCredential form,
    required CloudCredential? existing,
    required bool endpointUnchanged,
  }) {
    final username =
        form.username?.isNotEmpty == true ? form.username : existing?.username;
    final password =
        form.password?.isNotEmpty == true ? form.password : existing?.password;
    final unchanged =
        username == existing?.username && password == existing?.password;
    return CloudCredential(
      username: username,
      password: password,
      cookie: endpointUnchanged ? existing?.cookie : null,
      token: endpointUnchanged && unchanged ? existing?.token : null,
    );
  }

  static CloudCredential _mergeQuarkCredential({
    required CloudCredential form,
    required CloudCredential? existing,
  }) =>
      CloudCredential(
        cookie: form.cookie?.trim().isNotEmpty == true
            ? form.cookie
            : existing?.cookie,
      );

  static CloudCredential _mergeBaiduCredential({
    required CloudCredential form,
    required CloudCredential? existing,
  }) {
    final clientId = form.clientId?.trim().isNotEmpty == true
        ? form.clientId!.trim()
        : existing?.clientId;
    final clientSecret = form.clientSecret?.trim().isNotEmpty == true
        ? form.clientSecret!.trim()
        : existing?.clientSecret;
    final keysUnchanged = clientId == existing?.clientId &&
        clientSecret == existing?.clientSecret;
    final suppliedTokens = form.accessToken?.trim().isNotEmpty == true &&
        form.refreshToken?.trim().isNotEmpty == true;
    return CloudCredential(
      clientId: clientId,
      clientSecret: clientSecret,
      accessToken: suppliedTokens
          ? form.accessToken!.trim()
          : keysUnchanged
              ? existing?.accessToken
              : null,
      refreshToken: suppliedTokens
          ? form.refreshToken!.trim()
          : keysUnchanged
              ? existing?.refreshToken
              : null,
      accessTokenExpiresAt: suppliedTokens
          ? form.accessTokenExpiresAt
          : keysUnchanged
              ? existing?.accessTokenExpiresAt
              : null,
    );
  }

  static CloudDriveClient _createOpenListClient(
    CloudSource source,
    CloudCredentialStore credentialStore,
    bool allowSelfSignedCertificate,
  ) =>
      OpenListClient(
        source: source,
        credentialStore: credentialStore,
        allowSelfSignedCertificate: allowSelfSignedCertificate,
      );

  static CloudDriveClient _createQuarkClient(
    CloudSource source,
    CloudCredentialStore credentialStore,
    bool allowSelfSignedCertificate,
  ) =>
      QuarkDriveClient(
        source: source,
        credentialStore: credentialStore,
      );

  static CloudDriveClient _createBaiduClient(
    CloudSource source,
    CloudCredentialStore credentialStore,
    bool allowSelfSignedCertificate,
  ) =>
      BaiduDriveClient(
        source: source,
        credentialStore: credentialStore,
      );

  static CloudRangeRemoteReader _createQuarkRangeReader({
    required CloudSource source,
    required CloudPlaybackResource resource,
    required Future<CloudPlaybackResource> Function() refreshResource,
    required CloudCredentialStore credentialStore,
  }) =>
      QuarkRangeRemoteReader(
        resource: _toQuarkRemoteResource(resource),
        refreshResource: () async =>
            _toQuarkRemoteResource(await refreshResource()),
      );

  static CloudRangeRemoteReader _createBaiduRangeReader({
    required CloudSource source,
    required CloudPlaybackResource resource,
    required Future<CloudPlaybackResource> Function() refreshResource,
    required CloudCredentialStore credentialStore,
  }) =>
      BaiduRangeRemoteReader(
        resource: _toCloudRangeResource(resource),
        accessTokenProvider: () async {
          final credential = await credentialStore.read(source.id);
          final token = credential?.accessToken?.trim() ?? '';
          if (token.isEmpty) {
            throw const CloudRangeRemoteAuthenticationException('百度授权无效');
          }
          return token;
        },
        refreshResource: () async =>
            _toCloudRangeResource(await refreshResource()),
      );

  static QuarkRemoteResource _toQuarkRemoteResource(
    CloudPlaybackResource resource,
  ) =>
      QuarkRemoteResource(
        uri: resource.uri,
        headers: resource.headers,
      );

  static CloudRangeRemoteResource _toCloudRangeResource(
    CloudPlaybackResource resource,
  ) =>
      CloudRangeRemoteResource(uri: resource.uri);
}
