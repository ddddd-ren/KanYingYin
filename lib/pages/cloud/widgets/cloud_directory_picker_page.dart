import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/cloud/application/cloud_directory_address_resolver.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

typedef CloudDirectoryPickerResultBuilder<T> = T Function(
  List<CloudRemoteRef> selected,
);
typedef CloudDirectorySelectionKeyBuilder = String Function(
  CloudRemoteRef directory,
);

class CloudDirectoryPickerPage<T> extends StatefulWidget {
  const CloudDirectoryPickerPage({
    super.key,
    required this.title,
    required this.root,
    required this.initialSelection,
    required this.loader,
    required this.resultBuilder,
    this.singleSelection = false,
    this.selectionKeyBuilder,
  });

  final String title;
  final CloudRemoteRef root;
  final List<CloudRemoteRef> initialSelection;
  final CloudDirectoryLoader loader;
  final CloudDirectoryPickerResultBuilder<T> resultBuilder;
  final bool singleSelection;
  final CloudDirectorySelectionKeyBuilder? selectionKeyBuilder;

  @override
  State<CloudDirectoryPickerPage<T>> createState() =>
      _CloudDirectoryPickerPageState<T>();
}

class _CloudDirectoryPickerPageState<T>
    extends State<CloudDirectoryPickerPage<T>> {
  final Map<String, CloudRemoteRef> _selected = <String, CloudRemoteRef>{};
  late final TextEditingController _addressController;
  late CloudRemoteRef _current;
  List<CloudRemoteRef> _ancestry = const <CloudRemoteRef>[];
  List<CloudFileEntry> _directories = const <CloudFileEntry>[];
  String? _addressError;
  String? _errorMessage;
  bool _loading = true;
  int _navigationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.root;
    _addressController = TextEditingController(text: widget.root.path);
    for (final reference in widget.initialSelection) {
      _selected[_identityKey(reference)] = reference;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDirectory(widget.root, const <CloudRemoteRef>[]);
    });
  }

  @override
  void dispose() {
    _navigationGeneration++;
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory(
    CloudRemoteRef directory,
    List<CloudRemoteRef> ancestry,
  ) async {
    final generation = ++_navigationGeneration;
    setState(() {
      _loading = true;
      _addressError = null;
      _errorMessage = null;
    });
    try {
      final entries = await widget.loader(directory);
      if (!mounted || generation != _navigationGeneration) return;
      final directories = entries.where((entry) => entry.isDirectory).toList()
        ..sort(
          (left, right) =>
              left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        );
      setState(() {
        _current = directory;
        _ancestry = List<CloudRemoteRef>.unmodifiable(ancestry);
        _directories = List<CloudFileEntry>.unmodifiable(directories);
        _addressController.value = TextEditingValue(
          text: directory.path,
          selection: TextSelection.collapsed(offset: directory.path.length),
        );
      });
    } on Object {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _errorMessage = '目录加载失败，请重试');
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitAddress() async {
    final target = _addressController.text.trim();
    if (target.isEmpty) {
      setState(() => _addressError = '请输入文件夹地址');
      return;
    }
    final generation = ++_navigationGeneration;
    setState(() {
      _loading = true;
      _addressError = null;
      _errorMessage = null;
    });
    try {
      final resolution = await CloudDirectoryAddressResolver(
        loader: widget.loader,
      ).resolve(root: widget.root, targetPath: target);
      final entries = await widget.loader(resolution.current);
      if (!mounted || generation != _navigationGeneration) return;
      final directories = entries.where((entry) => entry.isDirectory).toList()
        ..sort(
          (left, right) =>
              left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        );
      setState(() {
        _current = resolution.current;
        _ancestry = resolution.ancestry;
        _directories = List<CloudFileEntry>.unmodifiable(directories);
        _addressController.value = TextEditingValue(
          text: resolution.current.path,
          selection: TextSelection.collapsed(
            offset: resolution.current.path.length,
          ),
        );
      });
    } on Object {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _addressError = '目录不存在或无法访问');
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(CloudFileEntry entry) {
    return _loadDirectory(
      CloudRemoteRef(id: entry.id, path: entry.remotePath),
      <CloudRemoteRef>[..._ancestry, _current],
    );
  }

  Future<void> _navigateUp() async {
    if (_ancestry.isEmpty) return;
    await _loadDirectory(
      _ancestry.last,
      _ancestry.take(_ancestry.length - 1).toList(growable: false),
    );
  }

  void _toggle(CloudRemoteRef reference, bool selected) {
    setState(() {
      if (widget.singleSelection) _selected.clear();
      if (selected) {
        _selected[_identityKey(reference)] = reference;
      } else {
        _selected.remove(_identityKey(reference));
      }
    });
  }

  void _toggleCurrent() {
    final selected = !_selected.containsKey(_identityKey(_current));
    _toggle(_current, selected);
  }

  void _complete() {
    final selected = _selected.values.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    Navigator.of(context).pop<T>(widget.resultBuilder(selected));
  }

  String _selectionKey(CloudRemoteRef reference) =>
      widget.selectionKeyBuilder?.call(reference) ?? reference.id;

  static String _identityKey(CloudRemoteRef reference) =>
      '${reference.id}|${reference.path}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            key: const ValueKey<String>('select-current-directory'),
            onPressed: _loading ? null : _toggleCurrent,
            icon: Icon(
              _selected.containsKey(_identityKey(_current))
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
            ),
            label: const Text('选择当前目录'),
          ),
          TextButton(
            onPressed: _selected.isEmpty ? null : _complete,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('确定'),
                const SizedBox(width: 6),
                Text('已选 ${_selected.length} 个'),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '上级目录',
                      onPressed:
                          _loading || _ancestry.isEmpty ? null : _navigateUp,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>(
                          'cloud-directory-address',
                        ),
                        controller: _addressController,
                        enabled: !_loading,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _submitAddress(),
                        decoration: InputDecoration(
                          hintText: '输入网盘文件夹地址',
                          prefixIcon: const Icon(
                            Icons.folder_outlined,
                            size: 20,
                          ),
                          suffixIcon: _loading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submitAddress,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('跳转'),
                    ),
                  ],
                ),
                if (_addressError != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: Text(
                      _addressError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          if (_errorMessage != null)
            MaterialBanner(
              content: Text(_errorMessage!),
              actions: [
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => _loadDirectory(_current, _ancestry),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _directories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_directories.isEmpty) {
      return const Center(child: Text('当前目录没有子文件夹'));
    }
    return ListView.builder(
      itemCount: _directories.length,
      itemBuilder: (context, index) {
        final entry = _directories[index];
        final reference = CloudRemoteRef(
          id: entry.id,
          path: entry.remotePath,
        );
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(entry.name),
          subtitle: Text(
            entry.remotePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: _loading ? null : () => _open(entry),
          trailing: Checkbox(
            key: ValueKey<String>('select-${_selectionKey(reference)}'),
            value: _selected.containsKey(_identityKey(reference)),
            onChanged:
                _loading ? null : (value) => _toggle(reference, value ?? false),
          ),
        );
      },
    );
  }
}
