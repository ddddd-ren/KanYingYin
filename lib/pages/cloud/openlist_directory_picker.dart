import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

class OpenListDirectoryPickerPage extends StatefulWidget {
  const OpenListDirectoryPickerPage({
    super.key,
    required this.source,
    required this.controller,
    this.credential,
  });

  final CloudSource source;
  final CloudLibraryController controller;
  final CloudCredential? credential;

  @override
  State<OpenListDirectoryPickerPage> createState() =>
      _OpenListDirectoryPickerPageState();
}

class _OpenListDirectoryPickerPageState
    extends State<OpenListDirectoryPickerPage> {
  final Set<String> _selectedPaths = <String>{};
  List<CloudFileEntry> _directories = <CloudFileEntry>[];
  String _currentPath = '/';
  String? _errorMessage;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedPaths.addAll(widget.source.rootPaths);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load('/'));
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final directories = await widget.controller.browseDirectories(
        widget.source,
        path,
        credential: widget.credential,
      );
      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _directories = directories;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _errorMessage = widget.controller.errorMessage ?? '目录加载失败';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _parentPath {
    if (_currentPath == '/') return null;
    final segments = _currentPath.split('/').where((part) => part.isNotEmpty);
    final parentSegments = segments.take(segments.length - 1).toList();
    return parentSegments.isEmpty ? '/' : '/${parentSegments.join('/')}';
  }

  void _toggle(String path, bool selected) {
    setState(() {
      if (selected) {
        _selectedPaths.add(path);
      } else {
        _selectedPaths.remove(path);
      }
    });
  }

  void _complete() {
    final result = _selectedPaths.toList()..sort();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择扫描目录'),
        actions: [
          TextButton(
            onPressed: _selectedPaths.isEmpty ? null : _complete,
            child: const Text('确定'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: IconButton(
              tooltip: '上级目录',
              onPressed: _loading || _parentPath == null
                  ? null
                  : () => _load(_parentPath!),
              icon: const Icon(Icons.arrow_upward),
            ),
            title: Text(_currentPath,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('已选择 ${_selectedPaths.length} 个扫描目录'),
            trailing: Checkbox(
              key: ValueKey<String>('select-$_currentPath'),
              value: _selectedPaths.contains(_currentPath),
              onChanged: _loading
                  ? null
                  : (value) => _toggle(_currentPath, value ?? false),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _load(_currentPath),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_directories.isEmpty) {
      return const Center(child: Text('当前目录没有子文件夹'));
    }
    return ListView.builder(
      itemCount: _directories.length,
      itemBuilder: (context, index) {
        final directory = _directories[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(directory.name),
          onTap: () => _load(directory.remotePath),
          trailing: Checkbox(
            key: ValueKey<String>('select-${directory.remotePath}'),
            value: _selectedPaths.contains(directory.remotePath),
            onChanged: (value) => _toggle(directory.remotePath, value ?? false),
          ),
        );
      },
    );
  }
}
