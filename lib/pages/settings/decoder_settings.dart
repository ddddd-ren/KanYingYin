import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/storage.dart';

class DecoderSettings extends StatefulWidget {
  const DecoderSettings({super.key});

  @override
  State<DecoderSettings> createState() => _DecoderSettingsState();
}

class _DecoderSettingsState extends State<DecoderSettings> {
  late final Box<Object?> setting = GStorage.setting;
  late final ValueNotifier<String> decoder = ValueNotifier<String>(
    normalizeHardwareDecoder(
      setting.getTyped<String>(
        SettingBoxKey.hardwareDecoder,
        defaultValue: defaultHardwareDecoder,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    setting.put(SettingBoxKey.hardwareDecoder, decoder.value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('解码方式'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '卡顿或只有声音没画面时，可以在这里切换 CPU 或硬解器。',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.7,
              ),
              itemCount: hardwareDecodersList.length,
              itemBuilder: (context, index) {
                final entry = hardwareDecodersList.entries.elementAt(index);
                return ValueListenableBuilder<String>(
                  valueListenable: decoder,
                  builder: (context, selectedDecoder, child) {
                    final selected = selectedDecoder == entry.key;
                    return Material(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          setting.put(SettingBoxKey.hardwareDecoder, entry.key);
                          setting.put(
                            SettingBoxKey.hAenable,
                            entry.key != 'no',
                          );
                          decoder.value = entry.key;
                        },
                        child: Center(
                          child: Text(
                            entry.value,
                            textAlign: TextAlign.center,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: decoder,
              builder: (context, value, child) {
                return Text(
                  hardwareDecoderDescriptions[value] ??
                      hardwareDecoderDescriptions[defaultHardwareDecoder]!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              '默认按清晰度选择；1080P/HLS/HEVC/4K 可优先尝试 D3D11 拷贝，异常时可切 CPU 兼容。',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
