import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';

class SuperResolutionSettings extends StatefulWidget {
  const SuperResolutionSettings({super.key});

  @override
  State<SuperResolutionSettings> createState() =>
      _SuperResolutionSettingsState();
}

class _SuperResolutionSettingsState extends State<SuperResolutionSettings> {
  late final TypedSettings setting = Modular.get<TypedSettings>();
  late bool promptOnEnable;
  late Anime4kPreference anime4kPreference = switch (setting.getTyped<int>(
    SettingBoxKey.defaultSuperResolutionType,
    defaultValue: 1,
  )) {
    2 => Anime4kPreference.efficiency,
    3 => Anime4kPreference.quality,
    _ => Anime4kPreference.off,
  };

  @override
  void initState() {
    super.initState();
    promptOnEnable = setting.getTyped<bool>(
      SettingBoxKey.superResolutionWarn,
      defaultValue: false,
    );
  }

  Future<void> _setPreference(Anime4kPreference? value) async {
    if (value == null) return;
    final stored = switch (value) {
      Anime4kPreference.off => 1,
      Anime4kPreference.efficiency => 2,
      Anime4kPreference.quality => 3,
    };
    await setting.put(SettingBoxKey.defaultSuperResolutionType, stored);
    if (!mounted) return;
    setState(() => anime4kPreference = value);
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return KSettingsScaffold(
      title: '超分辨率',
      body: KSettingsList(
        maxWidth: 1000,
        sections: [
          KSettingsSection(
              title: Text('Anime4K 动画画质增强',
                  style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                KSettingsTile<Anime4kPreference>.radioTile(
                  title: Text('关闭', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('不使用 Anime4K。',
                      style: TextStyle(fontFamily: fontFamily)),
                  radioValue: Anime4kPreference.off,
                  groupValue: anime4kPreference,
                  onChanged: _setPreference,
                ),
                KSettingsTile<Anime4kPreference>.radioTile(
                  title: Text('效率档', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('动画画面需要放大时使用轻量增强，优先保持流畅。',
                      style: TextStyle(fontFamily: fontFamily)),
                  radioValue: Anime4kPreference.efficiency,
                  groupValue: anime4kPreference,
                  onChanged: _setPreference,
                ),
                KSettingsTile<Anime4kPreference>.radioTile(
                  title: Text('质量档', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('动画画面需要放大时使用完整增强，显卡负载更高。',
                      style: TextStyle(fontFamily: fontFamily)),
                  radioValue: Anime4kPreference.quality,
                  groupValue: anime4kPreference,
                  onChanged: _setPreference,
                ),
                KSettingsTile<void>(
                  title:
                      Text('自适应说明', style: TextStyle(fontFamily: fontFamily)),
                  description: Text(
                    '窗口缩小或原始分辨率足够时会暂时关闭，不会更改默认选择。',
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
              ]),
          KSettingsSection(
            title: Text('默认行为', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              KSettingsTile<void>.switchTile(
                title: Text('关闭提示', style: TextStyle(fontFamily: fontFamily)),
                description: Text('关闭每次启用超分辨率时的提示',
                    style: TextStyle(fontFamily: fontFamily)),
                initialValue: promptOnEnable,
                onToggle: (value) async {
                  promptOnEnable = value ?? !promptOnEnable;
                  await setting.put(
                      SettingBoxKey.superResolutionWarn, promptOnEnable);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
