import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/diagnostic_log_exporter.dart';
import 'package:kanyingyin/utils/storage.dart';
// ignore_for_file: avoid_print

import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/utils/utils.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  Box<Object?> setting = GStorage.setting;
  late double defaultPlaySpeed;
  late double defaultShortcutForwardPlaySpeed;
  late int defaultAspectRatioType;
  late bool hAenable;
  late bool lowMemoryMode;
  late bool playResume;
  late bool showPlayerError;
  late bool playerDisableAnimations;
  late bool autoPlayNext;
  late bool localAutoLoadSubtitle;
  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;
  late int playerButtonSkipTime;
  late int playerArrowKeySkipTime;
  final MenuController playerAspectRatioMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    defaultPlaySpeed = setting.getTyped<double>(
      SettingBoxKey.defaultPlaySpeed,
      defaultValue: 1.0,
    );
    defaultShortcutForwardPlaySpeed = setting.getTyped<double>(
      SettingBoxKey.defaultShortcutForwardPlaySpeed,
      defaultValue: 2.0,
    );
    defaultAspectRatioType = setting.getTyped<int>(
      SettingBoxKey.defaultAspectRatioType,
      defaultValue: 1,
    );
    hAenable =
        setting.getTyped<bool>(SettingBoxKey.hAenable, defaultValue: true);
    lowMemoryMode = setting.getTyped<bool>(
      SettingBoxKey.lowMemoryMode,
      defaultValue: false,
    );
    playResume =
        setting.getTyped<bool>(SettingBoxKey.playResume, defaultValue: true);
    showPlayerError = setting.getTyped<bool>(
      SettingBoxKey.showPlayerError,
      defaultValue: true,
    );
    autoPlayNext =
        setting.getTyped<bool>(SettingBoxKey.autoPlayNext, defaultValue: true);
    localAutoLoadSubtitle = setting.getTyped<bool>(
      SettingBoxKey.localAutoLoadSubtitle,
      defaultValue: true,
    );
    backgroundPlayback = setting.getTyped<bool>(
      SettingBoxKey.backgroundPlayback,
      defaultValue: false,
    );
    playerDisableAnimations = setting.getTyped<bool>(
      SettingBoxKey.playerDisableAnimations,
      defaultValue: false,
    );
    brightnessVolumeGesture = setting.getTyped<bool>(
      SettingBoxKey.brightnessVolumeGesture,
      defaultValue: true,
    );

    playerButtonSkipTime = setting.getTyped<int>(
      SettingBoxKey.buttonSkipTime,
      defaultValue: 80,
    );
    playerArrowKeySkipTime = setting.getTyped<int>(
      SettingBoxKey.arrowKeySkipTime,
      defaultValue: 10,
    );
  }

  void onBackPressed(BuildContext context) {
    if (AppDialog.observer.hasAppDialog) {
      AppDialog.dismiss<void>();
      return;
    }
  }

  void updateDefaultPlaySpeed(double speed) {
    setting.put(SettingBoxKey.defaultPlaySpeed, speed);
    setState(() {
      defaultPlaySpeed = speed;
    });
  }

  void updateDefaultShortcutForwardPlaySpeed(double speed) {
    setting.put(SettingBoxKey.defaultShortcutForwardPlaySpeed, speed);
    setState(() {
      defaultShortcutForwardPlaySpeed = speed;
    });
  }

  void updateDefaultAspectRatioType(int type) {
    setting.put(SettingBoxKey.defaultAspectRatioType, type);
    setState(() {
      defaultAspectRatioType = type;
    });
  }

  Future<void> updateButtonSkipTime() async {
    final int? newButtonSkipTime = await _showSkipTimeChangeDialog(
        title: '顶部按钮快进时长', initialValue: playerButtonSkipTime.toString());
    print('新设置的顶部按钮快进时长: $newButtonSkipTime');

    if (newButtonSkipTime != null &&
        newButtonSkipTime != playerButtonSkipTime) {
      setting.put(SettingBoxKey.buttonSkipTime, newButtonSkipTime);
      setState(() {
        playerButtonSkipTime = newButtonSkipTime;
      });
    }
  }

  Future<int?> _showSkipTimeChangeDialog(
      {required String title, required String initialValue}) async {
    return AppDialog.show<int>(builder: (context) {
      String input = "";
      return AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          return TextField(
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly, // 只允许输入数字
            ],
            decoration: InputDecoration(
              floatingLabelBehavior:
                  FloatingLabelBehavior.never, // 控制label的显示方式
              labelText: initialValue,
            ),
            onChanged: (value) {
              input = value;
            },
          );
        }),
        actions: <Widget>[
          TextButton(
            onPressed: () => AppDialog.dismiss<void>(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              final int? newValue = int.tryParse(input);

              if (newValue == null) {
                AppDialog.showToast(message: '请输入数字');
                return;
              }

              if (newValue <= 0) {
                AppDialog.showToast(message: '请输入大于0的数字');
                return;
              }
              // 以新设置的值弹出
              AppDialog.dismiss(popWith: newValue);
            },
            child: const Text('确定'),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: KSettingsScaffold(
        title: '播放设置',
        description: '调整解码、渲染、字幕、音频和播放器行为。',
        body: KSettingsList(
          maxWidth: 1000,
          sections: [
            KSettingsSection(
              tiles: [
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    hAenable = value ?? !hAenable;
                    await setting.put(SettingBoxKey.hAenable, hAenable);
                    if (!hAenable) {
                      await setting.put(SettingBoxKey.hardwareDecoder, 'no');
                    } else if (normalizeHardwareDecoder(
                            setting.getTyped<String>(
                          SettingBoxKey.hardwareDecoder,
                          defaultValue: defaultHardwareDecoder,
                        )) ==
                        'no') {
                      await setting.put(
                        SettingBoxKey.hardwareDecoder,
                        defaultHardwareDecoder,
                      );
                    }
                    setState(() {});
                  },
                  title: Text('硬件解码', style: TextStyle(fontFamily: fontFamily)),
                  initialValue: hAenable,
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    await Modular.to.pushNamed('/settings/player/decoder');
                    if (mounted) {
                      hAenable = setting.getTyped<bool>(
                        SettingBoxKey.hAenable,
                        defaultValue: true,
                      );
                      setState(() {});
                    }
                  },
                  title: Text('解码方式', style: TextStyle(fontFamily: fontFamily)),
                  description: Text(
                      '当前：${hardwareDecoderLabel(setting.getTyped<String>(
                        SettingBoxKey.hardwareDecoder,
                        defaultValue: defaultHardwareDecoder,
                      ))}',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    lowMemoryMode = value ?? !lowMemoryMode;
                    await setting.put(
                        SettingBoxKey.lowMemoryMode, lowMemoryMode);
                    setState(() {});
                  },
                  title:
                      Text('低内存模式', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('禁用高级缓存以减少内存占用',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: lowMemoryMode,
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    Modular.to.pushNamed('/settings/player/super');
                  },
                  title: Text('超分辨率', style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            KSettingsSection(
              tiles: [
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    backgroundPlayback = value ?? !backgroundPlayback;
                    await setting.put(
                        SettingBoxKey.backgroundPlayback, backgroundPlayback);
                    setState(() {});
                  },
                  title: Text('后台播放', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('应用退到后台或熄屏时继续播放音频',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: backgroundPlayback,
                ),
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    playResume = value ?? !playResume;
                    await setting.put(SettingBoxKey.playResume, playResume);
                    setState(() {});
                  },
                  title: Text('自动跳转', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('跳转到上次播放位置',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: playResume,
                ),
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    autoPlayNext = value ?? !autoPlayNext;
                    await setting.put(SettingBoxKey.autoPlayNext, autoPlayNext);
                    setState(() {});
                  },
                  title: Text('自动连播', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('当前视频播放完毕后自动播放下一集',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: autoPlayNext,
                ),
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    localAutoLoadSubtitle = value ?? !localAutoLoadSubtitle;
                    await setting.put(SettingBoxKey.localAutoLoadSubtitle,
                        localAutoLoadSubtitle);
                    setState(() {});
                  },
                  title: Text('同名字幕', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('播放本地视频时自动加载同目录同名字幕',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: localAutoLoadSubtitle,
                ),
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    playerDisableAnimations = value ?? !playerDisableAnimations;
                    await setting.put(SettingBoxKey.playerDisableAnimations,
                        playerDisableAnimations);
                    setState(() {});
                  },
                  title: Text('禁用动画', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('禁用播放器内的过渡动画',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: playerDisableAnimations,
                ),
                if (!Utils.isDesktop())
                  KSettingsTile<bool>.switchTile(
                    onToggle: (value) async {
                      brightnessVolumeGesture =
                          value ?? !brightnessVolumeGesture;
                      await setting.put(SettingBoxKey.brightnessVolumeGesture,
                          brightnessVolumeGesture);
                      setState(() {});
                    },
                    title:
                        Text('滑动手势', style: TextStyle(fontFamily: fontFamily)),
                    description: Text('竖向滑动调节音量和亮度',
                        style: TextStyle(fontFamily: fontFamily)),
                    initialValue: brightnessVolumeGesture,
                  ),
              ],
            ),
            KSettingsSection(
              tiles: [
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    showPlayerError = value ?? !showPlayerError;
                    await setting.put(
                        SettingBoxKey.showPlayerError, showPlayerError);
                    setState(() {});
                  },
                  title: Text('错误提示', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('显示播放器内部错误提示',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: showPlayerError,
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    try {
                      await DiagnosticLogExporter().openLogDirectory();
                    } on Object {
                      AppDialog.showToast(message: '无法打开日志目录');
                    }
                  },
                  leading: const Icon(Icons.folder_open_outlined),
                  title:
                      Text('打开日志目录', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('自动记录运行信息，最多保留 10 个日志文件',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    try {
                      final file =
                          await DiagnosticLogExporter().exportToDownloads();
                      AppDialog.showToast(message: '诊断日志已导出：${file.path}');
                    } on Object {
                      AppDialog.showToast(message: '导出诊断日志失败');
                    }
                  },
                  leading: const Icon(Icons.archive_outlined),
                  title:
                      Text('导出诊断日志', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('生成已脱敏的 ZIP 文件，便于排查播放问题',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            KSettingsSection(
              tiles: [
                KSettingsTile<void>(
                  title: Text('默认倍速', style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultPlaySpeed,
                    min: 0.25,
                    max: 3,
                    divisions: 11,
                    label: '${defaultPlaySpeed}x',
                    onChanged: (value) {
                      updateDefaultPlaySpeed(
                          double.parse(value.toStringAsFixed(2)));
                    },
                  ),
                ),
                KSettingsTile<void>(
                  title:
                      Text('默认方向键倍速', style: TextStyle(fontFamily: fontFamily)),
                  description: Slider(
                    value: defaultShortcutForwardPlaySpeed,
                    min: 1.25,
                    max: 3,
                    divisions: 7,
                    label: '${defaultShortcutForwardPlaySpeed}x',
                    onChanged: (value) {
                      updateDefaultShortcutForwardPlaySpeed(
                          double.parse(value.toStringAsFixed(2)));
                    },
                  ),
                ),
                KSettingsTile<void>.navigation(
                  description: Slider(
                    value: playerArrowKeySkipTime.toDouble(),
                    min: 0,
                    max: 15,
                    divisions: 15,
                    label: '$playerArrowKeySkipTime秒',
                    onChanged: (value) {
                      final newArrowKeySkipTime = value.toInt();
                      print('新设置的方向键快进/快退时长: $newArrowKeySkipTime');

                      if (value != playerArrowKeySkipTime) {
                        setting.put(SettingBoxKey.arrowKeySkipTime,
                            newArrowKeySkipTime);
                        setState(() {
                          playerArrowKeySkipTime = newArrowKeySkipTime;
                        });
                      }
                    },
                  ),
                  title: Text('左右方向键的快进/快退秒数',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    await updateButtonSkipTime();
                  },
                  title: Text('跳过时长', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('顶栏跳过按钮的秒数',
                      style: TextStyle(fontFamily: fontFamily)),
                  value: Text('$playerButtonSkipTime 秒',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    if (playerAspectRatioMenuController.isOpen) {
                      playerAspectRatioMenuController.close();
                    } else {
                      playerAspectRatioMenuController.open();
                    }
                  },
                  title:
                      Text('默认视频比例', style: TextStyle(fontFamily: fontFamily)),
                  value: MenuAnchor(
                    consumeOutsideTap: true,
                    controller: playerAspectRatioMenuController,
                    builder: (_, __, ___) {
                      return Text(
                        aspectRatioTypeMap[defaultAspectRatioType] ?? '自动',
                        style: TextStyle(fontFamily: fontFamily),
                      );
                    },
                    menuChildren: [
                      for (final entry in aspectRatioTypeMap.entries)
                        MenuItemButton(
                          requestFocusOnHover: false,
                          onPressed: () =>
                              updateDefaultAspectRatioType(entry.key),
                          child: Container(
                            height: 48,
                            constraints: BoxConstraints(minWidth: 112),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  color: entry.key == defaultAspectRatioType
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                  fontFamily: fontFamily,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
