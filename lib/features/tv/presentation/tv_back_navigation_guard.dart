import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef TvExitCallback = FutureOr<void> Function();

class TvBackNavigationGuard extends StatefulWidget {
  const TvBackNavigationGuard({
    super.key,
    required this.enabled,
    required this.child,
    this.onExit,
  });

  final bool enabled;
  final Widget child;
  final TvExitCallback? onExit;

  @override
  State<TvBackNavigationGuard> createState() => _TvBackNavigationGuardState();
}

class _TvBackNavigationGuardState extends State<TvBackNavigationGuard> {
  bool _exitDialogOpen = false;
  bool _exitRequested = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.enabled,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.enabled) unawaited(_handleBack());
      },
      child: widget.child,
    );
  }

  Future<void> _handleBack() async {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (_isEditingText(primaryFocus)) {
      primaryFocus?.unfocus();
      return;
    }
    if (_exitDialogOpen || !mounted) return;

    _exitDialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope<bool>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          Navigator.of(dialogContext).pop(false);
        },
        child: AlertDialog(
          title: const Text('退出看影音？'),
          content: const Text('请点击”退出”按钮关闭应用。'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.exit_to_app),
              label: const Text('退出'),
            ),
          ],
        ),
      ),
    );
    _exitDialogOpen = false;
    if (shouldExit == true) await _requestExit();
  }

  bool _isEditingText(FocusNode? focusNode) {
    final context = focusNode?.context;
    if (context == null || focusNode?.hasFocus != true) return false;
    return context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null;
  }

  Future<void> _requestExit() async {
    if (_exitRequested) return;
    _exitRequested = true;
    final callback = widget.onExit;
    if (callback == null) {
      await SystemNavigator.pop();
    } else {
      await callback();
    }
  }
}
