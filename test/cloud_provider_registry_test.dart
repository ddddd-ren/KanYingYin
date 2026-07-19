import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';

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
      expect(registry.supportsSelfSignedCertificate(CloudSourceType.openList),
          isTrue);
      expect(registry.supportsSelfSignedCertificate(CloudSourceType.quark),
          isFalse);
      expect(registry.supportsShareTransfer(CloudSourceType.openList), isFalse);
      expect(registry.supportsShareTransfer(CloudSourceType.quark), isTrue);
      await client.close();
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

    test('映射提供商专属错误且夸克占位不会伪装可用', () {
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
      expect(
        () => registry.createClient(source, MemoryCloudCredentialStore()),
        throwsA(isA<CloudDriveException>()),
      );
    });
  });
}
