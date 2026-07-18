import 'package:hive_ce/hive.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/storage.dart';

class SubtitleStyleSettings {
  static const double defaultFontSize = 36.0;
  static const int defaultColorValue = 0xffffffff;
  static const int defaultBorderColorValue = 0xff000000;
  static const double defaultBorderSize = 2.0;
  static const bool defaultShadowEnabled = true;
  static const double defaultShadowOffset = 2.0;
  static const double defaultPosition = 90.0;
  static const bool defaultForceStyle = false;

  static const SubtitleStyleSettings defaults = SubtitleStyleSettings(
    fontSize: defaultFontSize,
    colorValue: defaultColorValue,
    borderColorValue: defaultBorderColorValue,
    borderSize: defaultBorderSize,
    shadowEnabled: defaultShadowEnabled,
    shadowOffset: defaultShadowOffset,
    position: defaultPosition,
    forceStyle: defaultForceStyle,
  );

  final double fontSize;
  final int colorValue;
  final int borderColorValue;
  final double borderSize;
  final bool shadowEnabled;
  final double shadowOffset;
  final double position;
  final bool forceStyle;

  const SubtitleStyleSettings({
    required this.fontSize,
    required this.colorValue,
    required this.borderColorValue,
    required this.borderSize,
    required this.shadowEnabled,
    required this.shadowOffset,
    required this.position,
    required this.forceStyle,
  });

  Color get color => Color(colorValue);

  Color get borderColor => Color(borderColorValue);
}

class SubtitlePreferences {
  SubtitlePreferences({Box<dynamic>? storage})
      : _storage = storage ?? GStorage.setting;

  final Box<dynamic> _storage;

  SubtitleStyleSettings loadStyle() {
    return SubtitleStyleSettings(
      fontSize: _boundedDouble(SettingBoxKey.subtitleFontSize,
          SubtitleStyleSettings.defaultFontSize, 18, 72),
      colorValue: _int(
          SettingBoxKey.subtitleColor, SubtitleStyleSettings.defaultColorValue),
      borderColorValue: _int(SettingBoxKey.subtitleBorderColor,
          SubtitleStyleSettings.defaultBorderColorValue),
      borderSize: _boundedDouble(SettingBoxKey.subtitleBorderSize,
          SubtitleStyleSettings.defaultBorderSize, 0, 8),
      shadowEnabled: _bool(SettingBoxKey.subtitleShadowEnabled,
          SubtitleStyleSettings.defaultShadowEnabled),
      shadowOffset: _boundedDouble(SettingBoxKey.subtitleShadowOffset,
          SubtitleStyleSettings.defaultShadowOffset, 0, 8),
      position: _boundedDouble(SettingBoxKey.subtitlePosition,
          SubtitleStyleSettings.defaultPosition, 60, 100),
      forceStyle: _bool(SettingBoxKey.subtitleForceStyle,
          SubtitleStyleSettings.defaultForceStyle),
    );
  }

  Future<void> saveStyle(SubtitleStyleSettings settings) async {
    await _storage.put(SettingBoxKey.subtitleFontSize,
        settings.fontSize.clamp(18, 72).toDouble());
    await _storage.put(SettingBoxKey.subtitleColor, settings.colorValue);
    await _storage.put(
        SettingBoxKey.subtitleBorderColor, settings.borderColorValue);
    await _storage.put(SettingBoxKey.subtitleBorderSize,
        settings.borderSize.clamp(0, 8).toDouble());
    await _storage.put(
        SettingBoxKey.subtitleShadowEnabled, settings.shadowEnabled);
    await _storage.put(SettingBoxKey.subtitleShadowOffset,
        settings.shadowOffset.clamp(0, 8).toDouble());
    await _storage.put(SettingBoxKey.subtitlePosition,
        settings.position.clamp(60, 100).toDouble());
    await _storage.put(SettingBoxKey.subtitleForceStyle, settings.forceStyle);
  }

  double loadDelay(String key) {
    final values = _delayMap();
    final value = values[key];
    if (value is! num) return 0.0;
    final converted = value.toDouble();
    if (!converted.isFinite || converted < -30 || converted > 30) return 0.0;
    return (converted * 2).round() / 2;
  }

  Future<void> saveDelay(String key, double seconds) async {
    if (key.isEmpty) return;
    final values = _delayMap();
    final normalized = _normalizeDelay(seconds);
    if (normalized == 0) {
      values.remove(key);
    } else {
      values[key] = normalized;
    }
    await _storage.put(SettingBoxKey.subtitleDelayByVideo, values);
  }

  Map<String, Object?> _delayMap() {
    final value = _storage.get(SettingBoxKey.subtitleDelayByVideo);
    if (value is! Map) return <String, Object?>{};
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  double _boundedDouble(String key, double fallback, double min, double max) {
    final value = _storage.get(key);
    if (value is! num) return fallback;
    final converted = value.toDouble();
    return converted >= min && converted <= max ? converted : fallback;
  }

  int _int(String key, int fallback) {
    final value = _storage.get(key);
    return value is int ? value : fallback;
  }

  bool _bool(String key, bool fallback) {
    final value = _storage.get(key);
    return value is bool ? value : fallback;
  }

  double _normalizeDelay(double value) {
    if (!value.isFinite) return 0.0;
    return ((value * 2).round() / 2).clamp(-30, 30).toDouble();
  }
}
