import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';

class RendererSettings extends StatefulWidget {
  const RendererSettings({super.key});

  @override
  State<RendererSettings> createState() => _RendererSettingsState();
}

class _RendererSettingsState extends State<RendererSettings> {
  late final Box<Object?> setting = GStorage.setting;
  late final ValueNotifier<String> renderer = ValueNotifier<String>(
    setting.getTyped<String>(
      SettingBoxKey.androidVideoRenderer,
      defaultValue: 'auto',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return KSettingsScaffold(
      title: '视频渲染器',
      body: KSettingsList(
        maxWidth: 1000,
        sections: [
          KSettingsSection(
            title: Text('选择合适的渲染器以获得最佳播放体验',
                style: TextStyle(fontFamily: fontFamily)),
            tiles: androidVideoRenderersList.entries
                .map((e) => KSettingsTile<String>.radioTile(
                      title:
                          Text(e.key, style: TextStyle(fontFamily: fontFamily)),
                      description: Text(e.value,
                          style: TextStyle(fontFamily: fontFamily)),
                      radioValue: e.key,
                      groupValue: renderer.value,
                      onChanged: (String? value) {
                        if (value != null) {
                          setting.put(
                              SettingBoxKey.androidVideoRenderer, value);
                          setState(() {
                            renderer.value = value;
                          });
                        }
                      },
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
