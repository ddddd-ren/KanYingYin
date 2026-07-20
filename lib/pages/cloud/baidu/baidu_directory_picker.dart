import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

class BaiduDirectoryPickerPage extends StatefulWidget {
  const BaiduDirectoryPickerPage({
    super.key,
    required this.source,
    required this.controller,
    required this.credential,
    this.initialSelection = const <CloudRemoteRef>[],
    this.title = '选择百度媒体目录',
  });

  final CloudSource source;
  final CloudLibraryController controller;
  final CloudCredential credential;
  final List<CloudRemoteRef> initialSelection;
  final String title;

  @override
  State<BaiduDirectoryPickerPage> createState() =>
      _BaiduDirectoryPickerPageState();
}

class _BaiduDirectoryPickerPageState extends State<BaiduDirectoryPickerPage> {
  final Map<String, CloudRemoteRef> _selected = <String, CloudRemoteRef>{};
  final List<CloudRemoteRef> _history = <CloudRemoteRef>[];
  List<CloudFileEntry> _directories = <CloudFileEntry>[];
  CloudRemoteRef _current = const CloudRemoteRef(id: '0', path: '/');
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    for (final reference in widget.initialSelection) {
      _selected[reference.id] = reference;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(_current));
  }

  Future<void> _load(
    CloudRemoteRef directory, {
    bool pushHistory = false,
  }) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final entries = await widget.controller.browseRemoteDirectories(
        widget.source,
        directory,
        credential: widget.credential,
      );
      if (!mounted) return;
      setState(() {
        if (pushHistory) _history.add(_current);
        _current = directory;
        _directories = entries;
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

  void _toggle(CloudRemoteRef reference, bool selected) {
    setState(() {
      if (selected) {
        _selected[reference.id] = reference;
      } else {
        _selected.remove(reference.id);
      }
    });
  }

  void _complete() {
    final result = _selected.values.toList()
      ..sort((first, second) => first.path.compareTo(second.path));
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _complete,
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
              onPressed: _loading || _history.isEmpty
                  ? null
                  : () {
                      final parent = _history.removeLast();
                      _load(parent);
                    },
              icon: const Icon(Icons.arrow_upward),
            ),
            title: Text(_current.path),
            subtitle: Text('已选择 ${_selected.length} 个目录'),
            trailing: Checkbox(
              key: ValueKey<String>('select-${_current.id}'),
              value: _selected.containsKey(_current.id),
              onChanged: _loading
                  ? null
                  : (value) => _toggle(_current, value ?? false),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_errorMessage!),
            ),
          Expanded(
            child: ListView.builder(
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
                  onTap: _loading
                      ? null
                      : () => _load(reference, pushHistory: true),
                  trailing: Checkbox(
                    key: ValueKey<String>('select-${entry.id}'),
                    value: _selected.containsKey(entry.id),
                    onChanged: _loading
                        ? null
                        : (value) => _toggle(reference, value ?? false),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
