import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_drive_client.dart';

void main() {
  group('CloudProviderRegistry', () {
    final registry = CloudProviderRegistry();

    test('创建正确客户端并集中声明提供商能力', () async {
      const openList = CloudSource(
        id: 'openlist-fixture',
        type: CloudSourceType.openList,
        name: 'OpenList',
        baseUrl: 'https://openlist.example.invalid/',
        rootPaths: <String>['/'],
        allowSelfSignedCertificate: true,
      );

      final client = registry.createClient(
        openList,
        MemoryCloudCredentialStore(),
      );

      expect(client, isA<OpenListClient>());
      expect(registry.providerName(CloudSourceType.openList), 'OpenList');
      expect(registry.providerName(CloudSourceType.quark), '夸克网盘');
      expect(registry.providerName(CloudSourceType.baidu), '百度网盘');
      expect(registry.supportsSelfSignedCertificate(CloudSourceType.openList),
          isTrue);
      expect(registry.supportsSelfSignedCertificate(CloudSourceType.quark),
          isFalse);
      expect(registry.supportsShareTransfer(CloudSourceType.openList), isFalse);
      expect(registry.supportsShareTransfer(CloudSourceType.quark), isTrue);
      expect(registry.supportsSelfSignedCertificate(CloudSourceType.baidu),
          isFalse);
      expect(registry.supportsShareTransfer(CloudSourceType.baidu), isFalse);
      await client.close();
    });

    test('百度来源固定使用官方地址且不支持分享写操作', () {
      const source = CloudSource(
        id: 'baidu-fixture',
        type: CloudSourceType.baidu,
        name: '百度网盘',
        baseUrl: 'https://example.invalid',
        rootPaths: <String>[],
        allowSelfSignedCertificate: true,
      );

      final normalized = registry.normalizeSource(source);

      expect(normalized.baseUrl, 'https://pan.baidu.com');
      expect(normalized.allowSelfSignedCertificate, isFalse);
      expect(registry.providerName(CloudSourceType.baidu), '百度网盘');
      expect(registry.supportsShareTransfer(CloudSourceType.baidu), isFalse);
    });

    test('百度凭据留空保留密钥且更换密钥清除旧令牌', () {
      const source = CloudSource(
        id: 'baidu-fixture',
        type: CloudSourceType.baidu,
        name: '百度网盘',
        baseUrl: 'https://pan.baidu.com',
        rootPaths: <String>[],
      );
      final expiresAt = DateTime.utc(2026, 8, 1);
      final existing = CloudCredential(
        clientId: 'client-old',
        clientSecret: 'secret-old',
        accessToken: 'access-old',
        refreshToken: 'refresh-old',
        accessTokenExpiresAt: expiresAt,
      );

      final unchanged = registry.mergeCredential(
        source: source,
        form: const CloudCredential(),
        existing: existing,
        endpointUnchanged: true,
      );
      final changed = registry.mergeCredential(
        source: source,
        form: const CloudCredential(
          clientId: 'client-new',
          clientSecret: 'secret-new',
        ),
        existing: existing,
        endpointUnchanged: true,
      );

      expect(unchanged.clientId, 'client-old');
      expect(unchanged.accessToken, 'access-old');
      expect(unchanged.accessTokenExpiresAt, expiresAt);
      expect(changed.clientId, 'client-new');
      expect(changed.clientSecret, 'secret-new');
      expect(changed.accessToken, isNull);
      expect(changed.refreshToken, isNull);
      expect(changed.accessTokenExpiresAt, isNull);
    });

    test('规范化来源并合并 OpenList 凭据', () {
      const source = CloudSource(
        id: 'openlist-fixture',
        type: CloudSourceType.openList,
        name: 'OpenList',
        baseUrl: 'https://openlist.example.invalid///',
        rootPaths: <String>['/'],
      );
      const existing = CloudCredential(
        username: 'alice',
        password: 'old-password',
        token: 'old-token',
      );

      final normalized = registry.normalizeSource(source);
      final unchanged = registry.mergeCredential(
        source: normalized,
        form: const CloudCredential(),
        existing: existing,
        endpointUnchanged: true,
      );
      final changed = registry.mergeCredential(
        source: normalized,
        form: const CloudCredential(password: 'new-password'),
        existing: existing,
        endpointUnchanged: true,
      );

      expect(normalized.baseUrl, 'https://openlist.example.invalid');
      expect(unchanged.username, 'alice');
      expect(unchanged.password, 'old-password');
      expect(unchanged.token, 'old-token');
      expect(changed.password, 'new-password');
      expect(changed.token, isNull);
    });

    test('映射提供商专属错误并创建夸克客户端', () async {
      const source = CloudSource(
        id: 'quark-fixture',
        type: CloudSourceType.quark,
        name: '夸克',
        baseUrl: '',
        rootPaths: <String>['/'],
      );

      expect(
        registry.errorMessage(
          CloudSourceType.openList,
          const CloudDriveException(CloudDriveErrorType.notFound),
        ),
        '未找到 OpenList 服务',
      );
      final client =
          registry.createClient(source, MemoryCloudCredentialStore());
      expect(client, isA<QuarkDriveClient>());
      await client.close();
    });
  });
}
