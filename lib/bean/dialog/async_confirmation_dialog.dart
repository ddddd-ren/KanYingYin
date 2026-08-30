import 'package:flutter/material.dart';

class AsyncConfirmationDialog extends StatefulWidget {
  const AsyncConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onConfirm,
    required this.errorMessage,
  });

  final String title;
  final Widget content;
  final String confirmLabel;
  final Future<void> Function() onConfirm;
  final String errorMessage;

  @override
  State<AsyncConfirmationDialog> createState() =>
      _AsyncConfirmationDialogState();
}

class _AsyncConfirmationDialogState extends State<AsyncConfirmationDialog> {
  bool _processing = false;
  String? _error;

  Future<void> _confirm() async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = widget.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.content,
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey<String>('async-confirmation-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _processing ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('async-confirmation-submit'),
            onPressed: _processing ? null : _confirm,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: _processing ? 0 : 1,
                  child: Text(widget.confirmLabel),
                ),
                if (_processing)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
