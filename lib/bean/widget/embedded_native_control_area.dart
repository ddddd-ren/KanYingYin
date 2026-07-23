import 'package:flutter/material.dart';

class EmbeddedNativeControlArea extends StatefulWidget {
  /// The widget won't draw anything, just a placeholder for native window control.
  /// It only works on macOS at the moment.
  /// windows and linux have no way to embed native window control into flutter view.
  const EmbeddedNativeControlArea({
    super.key,
    required this.child,
    this.requireOffset = true,
  });

  final Widget child;
  final bool requireOffset;

  @override
  State<StatefulWidget> createState() => _EmbeddedNativeControlAreaState();
}

class _EmbeddedNativeControlAreaState extends State<EmbeddedNativeControlArea> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: widget.child,
    );
  }
}
