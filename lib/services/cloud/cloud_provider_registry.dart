import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_drive_client.dart';

typedef CloudProviderClientFactory = CloudDriveClient Function(
  CloudSource source,
  CloudCredentialStore credentialStore,
  bool allowSelfSignedCertificate,
);

class CloudProviderRegistry {
  CloudProviderRegistry({
    Map<CloudSourceType, CloudProviderClientFactory> clientFactories =
        const <CloudSourceType, CloudProviderClientFactory>{},
  }) : _clientFactories = <CloudSourceType, CloudProviderClientFactory>{
          CloudSourceType.openList: _createOpenListClient,
          CloudSourceType.quark: _createQuarkClient,
          ...clientFactories,
        };

  final Map<CloudSourceType, CloudProviderClientFactory> _clientFactories;

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

  String providerName(CloudSourceType type) => switch (type) {
        CloudSourceType.openList => 'OpenList',
        CloudSourceType.quark => '夸克网盘',
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
        (_, CloudDriveErrorType.permission) => '当前账号没有访问权限',
        (_, CloudDriveErrorType.network) => '连接失败，请检查网络',
        (CloudSourceType.openList, CloudDriveErrorType.notFound) =>
          '未找到 OpenList 服务',
        (CloudSourceType.quark, CloudDriveErrorType.notFound) => '夸克目录或文件不存在',
        (_, CloudDriveErrorType.certificate) => '服务器证书不受信任',
        (_, CloudDriveErrorType.invalidAddress) => '服务器地址格式无效',
        (CloudSourceType.quark, CloudDriveErrorType.incompatible) =>
          '当前版本暂不兼容夸克接口',
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
}
