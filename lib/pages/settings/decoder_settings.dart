import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/player/application/player_platform_policy.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/constants.dart';

class DecoderSettings extends StatefulWidget {
  const DecoderSettings({super.key});

  @override
  State<DecoderSettings> createState() => _DecoderSettingsState();
}

class _DecoderSettingsState extends State<DecoderSettings> {
  late final TypedSettings setting = Modular.get<TypedSettings>();
  late final PlayerPlatformPolicy policy =
      PlayerPlatformPolicy(detectAppPlatform());
  late final Map<String, String> decoderOptions =
      Map<String, String>.fromEntries(
    hardwareDecodersList.entries.where(
      (entry) => policy.capabilities.hardwareDecoders.contains(entry.key),
    ),
  );
  late final ValueNotifier<String> decoder = ValueNotifier<String>(
    policy.normalizeDecoder(
      setting.getTyped<String>(
        policy.decoderSettingKey,
        defaultValue: 'auto',
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    setting.put(policy.decoderSettingKey, decoder.value);
  }

  @override
  void dispose() {
    decoder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return KSettingsScaffold(
      title: '解码方式',
      description: '卡顿或只有声音没画面时，可切换 CPU 或硬件解码器。',
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
              itemCount: decoderOptions.length,
              itemBuilder: (context, index) {
                final entry = decoderOptions.entries.elementAt(index);
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
                          setting.put(policy.decoderSettingKey, entry.key);
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
              policy.capabilities.isWindows
                  ? '默认按清晰度选择；1080P/HLS/HEVC/4K 可优先尝试 D3D11 拷贝，异常时可切 CPU 兼容。'
                  : 'Android 默认由 MediaCodec 自动选择；遇到兼容问题时可切换 CPU 解码。',
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
