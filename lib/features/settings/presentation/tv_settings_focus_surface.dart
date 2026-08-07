import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

class TvSettingsFocusSurface extends StatefulWidget {
  const TvSettingsFocusSurface({
    super.key,
    required this.child,
    required this.onPressed,
    this.enabled = true,
    this.autofocus = false,
    this.capabilities,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool enabled;
  final bool autofocus;
  final AppPlatformCapabilities? capabilities;

  @override
  State<TvSettingsFocusSurface> createState() => _TvSettingsFocusSurfaceState();
}

class _TvSettingsFocusSurfaceState extends State<TvSettingsFocusSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isTv = (widget.capabilities ?? detectAppPlatform()).isAndroidTv;
    if (!isTv) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
        if (!value) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_focused) return;
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        });
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (widget.enabled) widget.onPressed();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        child: AnimatedContainer(
          key: ValueKey<String>(
            _focused
                ? 'tv-settings-focused-surface'
                : 'tv-settings-unfocused-surface',
          ),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _focused
                ? scheme.primaryContainer.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: ExcludeFocus(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                widget.child,
                SizedBox(
                  height: 28,
                  child: AnimatedOpacity(
                    opacity: _focused ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '当前选中 · 按确认执行',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
