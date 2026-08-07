import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/player/application/player_color_profile.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';

class PlayerColorSettingsPage extends StatefulWidget {
  const PlayerColorSettingsPage({super.key, this.settings});

  final TypedSettings? settings;

  @override
  State<PlayerColorSettingsPage> createState() =>
      _PlayerColorSettingsPageState();
}

class _PlayerColorSettingsPageState extends State<PlayerColorSettingsPage> {
  late final TypedSettings setting =
      widget.settings ?? Modular.get<TypedSettings>();
  late PlayerColorProfile profile = PlayerColorProfileParsing.fromStorage(
    setting.getTyped<String>(
      SettingBoxKey.playerColorProfile,
      defaultValue: PlayerColorProfile.automatic.storageValue,
    ),
  );

  Future<void> _select(PlayerColorProfile? value) async {
    if (value == null) return;
    await setting.put(SettingBoxKey.playerColorProfile, value.storageValue);
    if (mounted) setState(() => profile = value);
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return KSettingsScaffold(
      title: '色彩输出',
      description: '选择 Windows 播放器的 HDR 与 SDR 处理方式；重新进入播放器后生效。',
      body: KSettingsList(
        maxWidth: 1000,
        sections: [
          KSettingsSection(
            tiles: [
              for (final option in PlayerColorProfile.values)
                KSettingsTile<PlayerColorProfile>.radioTile(
                  title: Text(
                    option.label,
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  description: Text(
                    option.description,
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  radioValue: option,
                  groupValue: profile,
                  onChanged: _select,
                ),
            ],
            bottomInfo: Text(
              'HDR 直通需要 Windows 已开启 HDR；若播放器不支持所需属性会自动回退，不影响视频播放。',
              style: TextStyle(fontFamily: fontFamily),
            ),
          ),
        ],
      ),
    );
  }
}
