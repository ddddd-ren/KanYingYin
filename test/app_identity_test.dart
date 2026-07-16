import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('使用独立的看影音应用身份', () {
    expect(AppIdentity.displayName, '看影音');
    expect(AppIdentity.packageName, 'kanyingyin');
    expect(AppIdentity.windowsIdentity, 'com.kanyingyin.player');
    expect(AppIdentity.storageNamespace, 'kanyingyin');
    expect(AppIdentity.supportsRemoteUpdates, isFalse);
  });
}
