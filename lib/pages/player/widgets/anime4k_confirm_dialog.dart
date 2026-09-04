import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';

Future<bool> showSuperResolutionConfirmDialog({
  required TypedSettings setting,
}) async {
  final result = await AppDialog.show<bool>(builder: (context) {
    bool dontAskAgain = false;

    return StatefulBuilder(builder: (context, setState) {
      return AlertDialog(
        title: const Text('性能提示'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('启用超分辨率（质量档）可能会造成设备卡顿，是否继续？'),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: dontAskAgain,
                  onChanged: (value) =>
                      setState(() => dontAskAgain = value ?? false),
                ),
                const Text('下次不再询问'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (dontAskAgain) {
                await setting.put(SettingBoxKey.superResolutionWarn, true);
              }
              AppDialog.dismiss<bool>(popWith: false);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (dontAskAgain) {
                await setting.put(SettingBoxKey.superResolutionWarn, true);
              }
              AppDialog.dismiss<bool>(popWith: true);
            },
            child: const Text('确认'),
          ),
        ],
      );
    });
  });

  return result ?? false;
}
