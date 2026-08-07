import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvBackShortcutScope extends StatelessWidget {
  const TvBackShortcutScope({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _handleBack,
        const SingleActivator(LogicalKeyboardKey.browserBack): _handleBack,
        const SingleActivator(LogicalKeyboardKey.goBack): _handleBack,
        const SingleActivator(LogicalKeyboardKey.navigatePrevious): _handleBack,
      },
      child: child,
    );
  }

  void _handleBack() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (_isEditingText(primaryFocus)) {
      primaryFocus?.unfocus();
      return;
    }
    final focusContext = primaryFocus?.context;
    if (focusContext == null) return;
    unawaited(_popNearestRoute(focusContext));
  }

  Future<void> _popNearestRoute(BuildContext context) async {
    final nearest = Navigator.maybeOf(context);
    final root = Navigator.maybeOf(context, rootNavigator: true);
    if (nearest != null && await nearest.maybePop()) return;
    if (root != null && !identical(root, nearest)) {
      await root.maybePop();
    }
  }

  bool _isEditingText(FocusNode? focusNode) {
    final context = focusNode?.context;
    if (context == null || focusNode?.hasFocus != true) return false;
    return context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null;
  }
}
