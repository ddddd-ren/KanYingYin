import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/core/network/network_config.dart';
import 'package:kanyingyin/utils/dio_logger_interceptor.dart';
import 'package:kanyingyin/utils/network_settings_config_factory.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> setting;

  setUpAll(() async {
    hiveDirectory = Directory.systemTemp.createTempSync(
      'kanyingyin-network-settings-',
    );
    Hive.init(hiveDirectory.path);
    setting = await Hive.openBox<dynamic>('network-settings-test');
  });

  setUp(() => setting.clear());

  tearDownAll(() async {
    await setting.close();
    hiveDirectory.deleteSync(recursive: true);
  });

  test('DioFactory 只安装调用方显式传入的拦截器', () {
    const config = NetworkConfig();
    final withoutInterceptors = DioFactory.createForConfig(config);
    final loggerInterceptor = DioLoggerInterceptor();
    final withInterceptor = DioFactory.createForConfig(
      config,
      interceptors: [loggerInterceptor],
    );

    expect(
      withoutInterceptors.interceptors.whereType<DioLoggerInterceptor>(),
      isEmpty,
    );
    expect(
      withInterceptor.interceptors.whereType<DioLoggerInterceptor>(),
      orderedEquals([loggerInterceptor]),
    );

    final networkConfigSource = File(
      'lib/core/network/network_config.dart',
    ).readAsStringSync();
    expect(networkConfigSource, isNot(contains('enableLog')));
  });

  test('代理配置保留系统 TLS 证书校验', () async {
    await setting.put(SettingBoxKey.proxyEnable, true);
    await setting.put(SettingBoxKey.proxyUrl, 'http://127.0.0.1:7890');

    final config = NetworkSettingsConfigFactory.create(setting: setting);

    expect(config.hasProxy, isTrue);
    expect(config.proxyHost, '127.0.0.1');
    expect(config.proxyPort, 7890);
    expect(config.allowBadCertificates, isFalse);
  });

  test('代理应用日志只承诺新建客户端读取已保存设置', () {
    final source = File('lib/utils/proxy_manager.dart').readAsStringSync();

    expect(source, contains('代理设置已保存，将对新建网络客户端生效'));
    expect(source, contains('代理清除设置已保存，将对新建网络客户端生效'));
    expect(source, isNot(contains('网络客户端配置已刷新')));
    expect(source, isNot(contains('网络客户端代理已清除')));
  });
}
