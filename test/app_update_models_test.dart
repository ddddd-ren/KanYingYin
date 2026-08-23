import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';

void main() {
  group('SemanticVersion', () {
    test('严格解析三段版本与 v 标签', () {
      expect(SemanticVersion.parse('2.1.168').toString(), '2.1.168');
      expect(SemanticVersion.parseTag('v2.1.168').toString(), '2.1.168');
      expect(() => SemanticVersion.parseTag('2.1.168'), throwsFormatException);
      expect(() => SemanticVersion.parseTag('v2.1'), throwsFormatException);
      expect(
        () => SemanticVersion.parseTag('v2.1.168-beta'),
        throwsFormatException,
      );
      expect(
        () => SemanticVersion.parse('02.1.168'),
        throwsFormatException,
      );
    });

    test('版本按三个数值字段排序并支持值相等', () {
      expect(
        SemanticVersion.parse('2.10.0').compareTo(
          SemanticVersion.parse('2.9.99'),
        ),
        greaterThan(0),
      );
      expect(
        SemanticVersion.parse('3.0.0').compareTo(
          SemanticVersion.parse('2.99.99'),
        ),
        greaterThan(0),
      );
      expect(
        SemanticVersion.parse('2.1.168'),
        SemanticVersion.parse('2.1.168'),
      );
    });
  });

  group('AppRelease', () {
    test('只接受唯一且版本匹配的 exe 资产', () {
      final release = _release(<AppReleaseAsset>[
        AppReleaseAsset(
          name: '看影音-2.1.168-测试版-安装程序.exe',
          size: 100,
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          downloadUri: Uri.parse('https://example.invalid/update.exe'),
        ),
        AppReleaseAsset(
          name: 'KanYingYin-2.1.168.apk',
          size: 50,
          sha256:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          downloadUri: Uri.parse('https://example.invalid/update.apk'),
        ),
      ]);

      expect(release.windowsInstaller.name, contains('2.1.168'));
    });

    test('拒绝没有匹配项或存在多个匹配项', () {
      expect(
        () => _release(<AppReleaseAsset>[]).windowsInstaller,
        throwsStateError,
      );
      expect(
        () => _release(<AppReleaseAsset>[
          _asset('KanYingYin-2.1.168.exe'),
          _asset('看影音-2.1.168-安装程序.exe'),
        ]).windowsInstaller,
        throwsStateError,
      );
    });
  });
}

AppRelease _release(List<AppReleaseAsset> assets) => AppRelease(
      version: SemanticVersion.parse('2.1.168'),
      tagName: 'v2.1.168',
      name: '看影音 2.1.168',
      body: '更新说明',
      publishedAt: DateTime.utc(2026, 8, 23),
      assets: assets,
    );

AppReleaseAsset _asset(String name) => AppReleaseAsset(
      name: name,
      size: 100,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      downloadUri: Uri.parse('https://example.invalid/$name'),
    );
