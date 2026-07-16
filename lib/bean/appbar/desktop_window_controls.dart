import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _alwaysOnTop = false;
  bool _maximized = false;
  bool _closeHovered = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshState() async {
    final alwaysOnTop = await windowManager.isAlwaysOnTop();
    final maximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() {
      _alwaysOnTop = alwaysOnTop;
      _maximized = maximized;
    });
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  void _setMaximized(bool value) {
    if (mounted) setState(() => _maximized = value);
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_alwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) setState(() => _alwaysOnTop = next);
  }

  Future<void> _toggleMaximized() async {
    if (_maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            tooltip: _alwaysOnTop ? '取消置顶' : '窗口置顶',
            icon: _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
            color: color,
            onPressed: _toggleAlwaysOnTop,
          ),
          _button(
            tooltip: '最小化',
            icon: Icons.remove,
            color: color,
            onPressed: windowManager.minimize,
          ),
          _button(
            tooltip: _maximized ? '还原' : '最大化',
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            color: color,
            onPressed: _toggleMaximized,
          ),
          MouseRegion(
            onEnter: (_) => setState(() => _closeHovered = true),
            onExit: (_) => setState(() => _closeHovered = false),
            child: _button(
              tooltip: '关闭',
              icon: Icons.close,
              color: _closeHovered ? Colors.white : color,
              backgroundColor:
                  _closeHovered ? const Color(0xFFC42B1C) : Colors.transparent,
              onPressed: windowManager.close,
            ),
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    Color backgroundColor = Colors.transparent,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 40,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(),
            backgroundColor: backgroundColor,
            padding: EdgeInsets.zero,
          ),
          icon: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
