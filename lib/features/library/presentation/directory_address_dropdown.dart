import 'dart:async';

import 'package:flutter/material.dart';

typedef DirectoryChildrenLoader = Future<List<DirectoryNavigationItem>>
    Function(String path);
typedef DirectoryChildSelected = FutureOr<void> Function(
  DirectoryNavigationItem item,
);
typedef DirectoryAddressSubmit = Future<String?> Function(String path);

class DirectoryNavigationItem {
  const DirectoryNavigationItem({
    required this.label,
    required this.path,
    this.subtitle,
  });

  final String label;
  final String path;
  final String? subtitle;
}

String normalizeDirectoryAddress(String value) {
  var normalized = value.trim();
  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}

/// 可编辑地址框，并按需下拉当前目录的直接子文件夹。
class DirectoryAddressDropdown extends StatefulWidget {
  const DirectoryAddressDropdown({
    super.key,
    required this.currentPath,
    required this.enabled,
    required this.loadChildren,
    required this.onChildSelected,
    required this.onSubmitted,
    this.addressKey = const ValueKey<String>('directory-address'),
    this.hintText = '输入文件夹地址',
  });

  final String currentPath;
  final bool enabled;
  final DirectoryChildrenLoader loadChildren;
  final DirectoryChildSelected onChildSelected;
  final DirectoryAddressSubmit onSubmitted;
  final Key addressKey;
  final String hintText;

  @override
  State<DirectoryAddressDropdown> createState() =>
      _DirectoryAddressDropdownState();
}

class _DirectoryAddressDropdownState extends State<DirectoryAddressDropdown> {
  final MenuController _menuController = MenuController();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  List<DirectoryNavigationItem> _children = const <DirectoryNavigationItem>[];
  String? _error;
  bool _loadingChildren = false;
  bool _submitting = false;
  int _operationGeneration = 0;

  bool get _disabled => !widget.enabled || _loadingChildren || _submitting;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant DirectoryAddressDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath == widget.currentPath) return;
    _controller.value = TextEditingValue(
      text: widget.currentPath,
      selection: TextSelection.collapsed(offset: widget.currentPath.length),
    );
    _error = null;
    if (_menuController.isOpen) _menuController.close();
  }

  @override
  void dispose() {
    _operationGeneration++;
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleChildren() async {
    if (_menuController.isOpen) {
      _menuController.close();
      return;
    }
    if (_disabled) return;
    final generation = ++_operationGeneration;
    setState(() {
      _loadingChildren = true;
      _error = null;
    });
    try {
      final children = await widget.loadChildren(widget.currentPath);
      if (!mounted || generation != _operationGeneration) return;
      setState(() {
        _children = List<DirectoryNavigationItem>.unmodifiable(children);
        _loadingChildren = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _operationGeneration) return;
        _menuController.open();
      });
    } on Object {
      if (!mounted || generation != _operationGeneration) return;
      setState(() {
        _loadingChildren = false;
        _error = '目录不存在或无法访问';
      });
    }
  }

  Future<void> _selectChild(DirectoryNavigationItem item) async {
    _menuController.close();
    try {
      await widget.onChildSelected(item);
    } on Object {
      if (!mounted) return;
      setState(() => _error = '目录不存在或无法访问');
    }
  }

  Future<void> _submit() async {
    final path = normalizeDirectoryAddress(_controller.text);
    if (path.isEmpty) {
      setState(() => _error = '请输入文件夹地址');
      return;
    }
    if (_menuController.isOpen) _menuController.close();
    final generation = ++_operationGeneration;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSubmitted(path);
    } on Object {
      error = '目录不存在或无法访问';
    }
    if (!mounted || generation != _operationGeneration) return;
    setState(() {
      _submitting = false;
      _error = error;
      if (error == null) {
        _controller.value = TextEditingValue(
          text: path,
          selection: TextSelection.collapsed(offset: path.length),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuAnchor(
          controller: _menuController,
          alignmentOffset: const Offset(0, 4),
          style: const MenuStyle(
            maximumSize: WidgetStatePropertyAll<Size>(Size(360, 320)),
          ),
          menuChildren: _menuItems(context),
          builder: (context, controller, child) => TextField(
            key: widget.addressKey,
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_disabled,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.folder_outlined, size: 18),
              suffixIcon: _loadingChildren || _submitting
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: '展开子文件夹',
                      onPressed: _disabled ? null : _toggleChildren,
                      icon: Icon(
                        controller.isOpen
                            ? Icons.arrow_drop_up_rounded
                            : Icons.arrow_drop_down_rounded,
                        size: 20,
                      ),
                    ),
              isDense: true,
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text(
              _error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.error,
                  ),
            ),
          ),
      ],
    );
  }

  List<Widget> _menuItems(BuildContext context) {
    if (_children.isEmpty) {
      return const <Widget>[
        MenuItemButton(
          onPressed: null,
          child: Text('没有子文件夹'),
        ),
      ];
    }
    final colors = Theme.of(context).colorScheme;
    return <Widget>[
      for (final item in _children)
        MenuItemButton(
          onPressed: () => _selectChild(item),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.subtitle case final subtitle?)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }
}
