enum PlayerColorProfile { automatic, hdrPassthrough, hdrToSdr }

extension PlayerColorProfileParsing on PlayerColorProfile {
  String get storageValue => name;

  String get label => switch (this) {
        PlayerColorProfile.automatic => '自动',
        PlayerColorProfile.hdrPassthrough => 'HDR 直通',
        PlayerColorProfile.hdrToSdr => 'HDR 转 SDR',
      };

  String get description => switch (this) {
        PlayerColorProfile.automatic => '跟随视频和设备默认色彩处理',
        PlayerColorProfile.hdrPassthrough => '电视支持 HDR 时保留 HDR 输出',
        PlayerColorProfile.hdrToSdr => '将 HDR 映射为 SDR，适合普通显示器',
      };

  static PlayerColorProfile fromStorage(String value) => switch (value) {
        'hdrPassthrough' => PlayerColorProfile.hdrPassthrough,
        'hdrToSdr' => PlayerColorProfile.hdrToSdr,
        _ => PlayerColorProfile.automatic,
      };
}

class PlayerColorDecision {
  const PlayerColorDecision({
    required this.requested,
    required this.effective,
    required this.properties,
    this.fallbackReason,
  });

  final PlayerColorProfile requested;
  final PlayerColorProfile effective;
  final Map<String, String> properties;
  final String? fallbackReason;

  bool get isFallback => fallbackReason != null;
}

class PlayerColorProfilePolicy {
  const PlayerColorProfilePolicy._();

  static PlayerColorDecision resolve(
    PlayerColorProfile profile, {
    required bool hdrOutputSupported,
  }) {
    if (profile == PlayerColorProfile.hdrPassthrough && !hdrOutputSupported) {
      return const PlayerColorDecision(
        requested: PlayerColorProfile.hdrPassthrough,
        effective: PlayerColorProfile.automatic,
        properties: <String, String>{},
        fallbackReason: '当前设备未报告 HDR 输出能力',
      );
    }
    return PlayerColorDecision(
      requested: profile,
      effective: profile,
      properties: _propertiesFor(profile),
    );
  }

  static Map<String, String> _propertiesFor(PlayerColorProfile profile) {
    return switch (profile) {
      PlayerColorProfile.automatic => const <String, String>{},
      PlayerColorProfile.hdrPassthrough => const <String, String>{
          'target-colorspace-hint': 'yes',
        },
      PlayerColorProfile.hdrToSdr => const <String, String>{
          'tone-mapping': 'bt.2390',
          'target-prim': 'bt.709',
          'target-trc': 'bt.1886',
          'target-peak': '100',
        },
    };
  }
}

typedef PlayerColorPropertySetter = Future<void> Function(
  String property,
  String value,
);

class PlayerColorProfileApplier {
  const PlayerColorProfileApplier(this._setProperty);

  final PlayerColorPropertySetter _setProperty;

  static const Map<String, String> _automaticValues = <String, String>{
    'target-colorspace-hint': 'no',
    'tone-mapping': 'auto',
    'target-prim': 'auto',
    'target-trc': 'auto',
    'target-peak': 'auto',
  };

  Future<PlayerColorDecision> apply(
    PlayerColorProfile profile, {
    required bool hdrOutputSupported,
  }) async {
    final decision = PlayerColorProfilePolicy.resolve(
      profile,
      hdrOutputSupported: hdrOutputSupported,
    );
    if (decision.properties.isEmpty) return decision;

    try {
      for (final property in decision.properties.entries) {
        await _setProperty(property.key, property.value);
      }
      return decision;
    } on Object catch (error) {
      for (final property in _automaticValues.entries) {
        try {
          await _setProperty(property.key, property.value);
        } on Object {
          // 某个重置属性不受当前 libmpv 支持时继续恢复其他属性。
        }
      }
      return PlayerColorDecision(
        requested: profile,
        effective: PlayerColorProfile.automatic,
        properties: const <String, String>{},
        fallbackReason: '播放器不支持所选色彩方案：${error.runtimeType}',
      );
    }
  }
}
