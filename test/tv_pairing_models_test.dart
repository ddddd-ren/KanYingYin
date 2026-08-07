import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

void main() {
  test('配对令牌为 32 字节、五分钟有效且只能消费一次', () {
    final now = DateTime.utc(2026, 8, 6, 12);
    final session = TvPairingSession.issue(
      now: now,
      random: Random(7),
    );

    expect(base64Url.decode(base64Url.normalize(session.token)), hasLength(32));
    expect(session.isExpired(DateTime.utc(2026, 8, 6, 12, 4)), isFalse);
    expect(session.isExpired(DateTime.utc(2026, 8, 6, 12, 5)), isTrue);
    expect(session.consume(session.token, now: now), isTrue);
    expect(session.consume(session.token, now: now), isFalse);
    expect(session.consume('wrong-token', now: now), isFalse);
  });

  test('二维码载荷只包含地址、端口、一次性令牌和协议版本', () {
    const payload = TvPairingQrPayload(
      host: '192.168.1.10',
      port: 38765,
      pairingToken: 'temporary-token',
      protocolVersion: TvPairingPayload.currentProtocolVersion,
    );

    expect(payload.toJson().keys.toSet(), {
      'host',
      'port',
      'pairingToken',
      'protocolVersion',
    });
    final uri = Uri.parse(payload.toQrData());
    expect(uri.host, '192.168.1.10');
    expect(uri.port, 38765);
    expect(uri.path, '/pair');
    expect(uri.queryParameters, {
      'token': 'temporary-token',
      'v': '2',
    });
    expect(payload.toQrData(), isNot(contains('password')));
    expect(payload.toQrData(), isNot(contains('tmdb')));
  });

  test('配对载荷复用便携配置且字符串不泄漏秘密', () {
    final payload = TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '手机配置',
      configuration: PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: 'phone-web',
        tmdbApiKey: 'tmdb-secret',
        cloudSources: <PortableCloudSourceConfiguration>[
          PortableCloudSourceConfiguration.fromSource(
            source: const CloudSource(
              id: 'quark-1',
              type: CloudSourceType.quark,
              name: '夸克',
              baseUrl: 'https://pan.quark.cn',
              rootPaths: <String>[],
            ),
            credential: const CloudCredential(cookie: 'cookie-secret'),
          ),
        ],
      ),
    );

    final restored = TvPairingPayload.decode(payload.encode());

    expect(restored.deviceName, '手机配置');
    expect(restored.configuration.tmdbApiKey, 'tmdb-secret');
    expect(restored.configuration.cloudSources.single.source.id, 'quark-1');
    expect(
      restored.configuration.cloudSources.single.credential?.cookie,
      'cookie-secret',
    );
    expect(restored.toString(), isNot(contains('tmdb-secret')));
    expect(restored.toString(), isNot(contains('cookie-secret')));
  });

  test('超过 256KB 的配置载荷被拒绝', () {
    final payload = TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '电视',
      configuration: PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: 'phone-web',
        tmdbApiKey: '',
        cloudSources: <PortableCloudSourceConfiguration>[
          PortableCloudSourceConfiguration.fromSource(
            source: const CloudSource(
              id: 'quark-large',
              type: CloudSourceType.quark,
              name: '夸克',
              baseUrl: 'https://pan.quark.cn',
              rootPaths: <String>[],
            ),
            credential: CloudCredential(
              cookie: 'a' * (TvPairingPayload.maxPayloadBytes + 1),
            ),
          ),
        ],
      ),
    );

    expect(payload.encode, throwsA(isA<TvPairingPayloadTooLargeException>()));
  });

  test('协议版本必须是整数且旧版扁平载荷不再接受', () {
    expect(
      () => TvPairingPayload.fromJson(<String, Object?>{
        'protocolVersion': 1.0,
        'deviceName': '电视',
        'configuration': <String, Object?>{},
      }),
      throwsA(isA<TvPairingInvalidPayloadException>()),
    );
    expect(
      () => TvPairingPayload.fromJson(<String, Object?>{
        'protocolVersion': 1,
        'deviceName': '电视',
        'tmdbApiKey': '',
        'cloudSources': <Object?>[],
      }),
      throwsA(isA<TvPairingInvalidPayloadException>()),
    );
  });

  test('配对载荷支持两类导入文件引用且不泄漏配置密码', () {
    final payload = TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '电视',
      configuration: PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: 'phone-web',
        tmdbApiKey: '',
        cloudSources: const <PortableCloudSourceConfiguration>[],
      ),
      fileIds: const <TvPairingFileKind, String>{
        TvPairingFileKind.configuration: 'config-file',
        TvPairingFileKind.scrapedMetadata: 'meta-file',
      },
      configurationFilePassword: 'password-secret',
    );

    final restored = TvPairingPayload.decode(payload.encode());

    expect(restored.fileIds, payload.fileIds);
    expect(restored.configurationFilePassword, 'password-secret');
    expect(restored.toString(), isNot(contains('password-secret')));
  });

  test('配置文件引用必须携带密码且只允许两种扩展名', () {
    expect(
      () => TvPairingPayload.fromJson(<String, Object?>{
        'protocolVersion': TvPairingPayload.currentProtocolVersion,
        'deviceName': '电视',
        'configuration': <String, Object?>{},
        'fileIds': <String, Object?>{'configuration': 'file-id'},
      }),
      throwsA(isA<TvPairingInvalidPayloadException>()),
    );
    expect(
      () => TvPairingFileKind.fromWireValue('unknown'),
      throwsA(isA<TvPairingInvalidPayloadException>()),
    );
  });
}
