import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';

class SetDisplayMode extends StatefulWidget {
  const SetDisplayMode({super.key});

  @override
  State<SetDisplayMode> createState() => _SetDisplayModeState();
}

class _SetDisplayModeState extends State<SetDisplayMode> {
  List<DisplayMode> modes = <DisplayMode>[];
  DisplayMode? active;
  DisplayMode? preferred;
  Box<Object?> setting = GStorage.setting;

  final ValueNotifier<int> page = ValueNotifier<int>(0);
  late final PageController controller = PageController()
    ..addListener(() {
      page.value = controller.page!.round();
    });

  @override
  void initState() {
    super.initState();
    init();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      fetchAll();
    });
  }

  Future<void> fetchAll() async {
    preferred = await FlutterDisplayMode.preferred;
    active = await FlutterDisplayMode.active;
    await setting.put(SettingBoxKey.displayMode, preferred.toString());
    setState(() {});
  }

  Future<void> init() async {
    try {
      modes = await FlutterDisplayMode.supported;
    } on PlatformException catch (_) {}
    var res = await getDisplayModeType(modes);

    preferred = modes.toList().firstWhere((el) => el == res);
    FlutterDisplayMode.setPreferredMode(preferred!);
  }

  Future<DisplayMode> getDisplayModeType(List<DisplayMode> modes) async {
    var value = setting.get(SettingBoxKey.displayMode);
    DisplayMode f = DisplayMode.auto;
    if (value != null) {
      f = modes.firstWhere((e) => e.toString() == value);
    }
    return f;
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return KSettingsScaffold(
      title: '屏幕帧率设置',
      body: (modes.isEmpty)
          ? const CircularProgressIndicator()
          : KSettingsList(
              maxWidth: 1000,
              sections: [
                KSettingsSection(
                  title: Text('没有生效? 重启app试试',
                      style: TextStyle(fontFamily: fontFamily)),
                  tiles: modes
                      .map((e) => KSettingsTile<DisplayMode>.radioTile(
                            radioValue: e,
                            groupValue: preferred,
                            onChanged: (DisplayMode? newMode) async {
                              await FlutterDisplayMode.setPreferredMode(
                                  newMode!);
                              await Future<dynamic>.delayed(
                                const Duration(milliseconds: 100),
                              );
                              await fetchAll();
                            },
                            title: e == DisplayMode.auto
                                ? Text('自动',
                                    style: TextStyle(fontFamily: fontFamily))
                                : Text('$e${e == active ? "  [系统]" : ""}',
                                    style: TextStyle(fontFamily: fontFamily)),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }
}
