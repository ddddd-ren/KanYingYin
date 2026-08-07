import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvFocusSurface extends StatefulWidget {
  const TvFocusSurface({
    super.key,
    required this.child,
    this.autofocus = false,
    this.enabled = true,
    this.onPressed,
    this.onFocusChange,
    this.reserveFocusSpace = true,
    this.focusedScale = 1.04,
    this.focusBorderWidth = 2,
    this.focusNode,
  });

  final Widget child;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;
  final bool reserveFocusSpace;
  final double focusedScale;
  final double focusBorderWidth;
  final FocusNode? focusNode;

  @override
  State<TvFocusSurface> createState() => _TvFocusSurfaceState();
}

class _TvFocusSurfaceState extends State<TvFocusSurface> {
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onPressed != null;

  void _handleFocusChange(bool focused) {
    if (_focused == focused) return;
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding:
          widget.reserveFocusSpace ? const EdgeInsets.all(6) : EdgeInsets.zero,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        enabled: _enabled,
        focusNode: widget.focusNode,
        onFocusChange: _handleFocusChange,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_enabled) widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          enabled: _enabled,
          child: AnimatedScale(
            scale: _focused ? widget.focusedScale : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              key: ValueKey<String>(
                _focused ? 'tv-focused-surface' : 'tv-unfocused-surface',
              ),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: _focused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.36),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _focused ? colors.primary : Colors.transparent,
                  width: widget.focusBorderWidth,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
