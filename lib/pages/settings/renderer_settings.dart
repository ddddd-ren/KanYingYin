import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/player/application/player_platform_policy.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/constants.dart';

class RendererSettingsPage extends StatefulWidget {
  const RendererSettingsPage({super.key});

  @override
  State<RendererSettingsPage> createState() => _RendererSettingsPageState();
}

class _RendererSettingsPageState extends State<RendererSettingsPage> {
  late final TypedSettings setting = Modular.get<TypedSettings>();
  late final PlayerPlatformPolicy policy =
      PlayerPlatformPolicy(detectAppPlatform());
  late String renderer = policy.normalizeRenderer(
        setting.getTyped<String>(
          SettingBoxKey.androidVideoRenderer,
          defaultValue: 'auto',
        ),
      ) ??
      'auto';

  Future<void> _select(String value) async {
    final normalized = policy.normalizeRenderer(value) ?? 'auto';
    await setting.put(SettingBoxKey.androidVideoRenderer, normalized);
    if (mounted) setState(() => renderer = normalized);
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return KSettingsScaffold(
      title: '视频渲染器',
      description: '选择 Android 视频输出方式；切换后重新进入播放器生效。',
      body: KSettingsList(
        maxWidth: 1000,
        sections: [
          KSettingsSection(
            tiles: [
              for (final entry in androidVideoRenderersList.entries)
                KSettingsTile<String>.radioTile(
                  title: Text(
                    entry.value,
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  description: entry.key == 'mediacodec_embed'
                      ? Text(
                          '低功耗嵌入式渲染，不支持 Anime4K。',
                          style: TextStyle(fontFamily: fontFamily),
                        )
                      : null,
                  radioValue: entry.key,
                  groupValue: renderer,
                  onChanged: (value) {
                    if (value != null) _select(value);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
