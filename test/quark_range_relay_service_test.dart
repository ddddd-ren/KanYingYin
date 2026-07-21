import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('夸克中转服务只构造读取器并委托公共服务', () {
    final source = File(
      'lib/services/cloud/quark/quark_range_relay_service.dart',
    ).readAsStringSync();

    expect(source, contains('CloudRangeRelayService'));
    expect(source, contains('QuarkRangeRemoteReader'));
    expect(source, contains("providerKey: 'quark'"));
    expect(source, contains("providerName: '夸克'"));
    expect(source, isNot(contains('HttpServer.bind')));
  });
}
