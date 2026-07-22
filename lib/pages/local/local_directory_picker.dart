import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

typedef LocalDriveRootsProvider = Future<List<String>> Function();
typedef LocalDirectoryLoader = Future<List<String>> Function(String path);

String normalizeLocalDirectoryAddress(String value) {
  var normalized = value.trim();
  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}

class LocalDirectoryPickerPage extends StatefulWidget {
  const LocalDirectoryPickerPage({
    super.key,
    this.initialPath,
    this.driveRootsProvider = discoverWindowsDriveRoots,
    this.directoryLoader = loadLocalDirectories,
  });

  final String? initialPath;
  final LocalDriveRootsProvider driveRootsProvider;
  final LocalDirectoryLoader directoryLoader;

  static Future<String?> pick(
    BuildContext context, {
    String? initialPath,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LocalDirectoryPickerPage(initialPath: initialPath),
      ),
    );
  }

  @override
  State<LocalDirectoryPickerPage> createState() =>
      _LocalDirectoryPickerPageState();
}

class _LocalDirectoryPickerPageState extends State<LocalDirectoryPickerPage> {
  late final TextEditingController _addressController;
  List<String> _entries = <String>[];
  String? _currentPath;
  String? _errorMessage;
  String? _addressError;
  bool _loading = true;
  int _navigationGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialPath?.trim() ?? '';
    _addressController = TextEditingController(text: initialPath);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initialPath.isEmpty) {
        _loadDrives();
      } else {
        _loadDirectory(initialPath);
      }
    });
  }

  @override
  void dispose() {
    _navigationGeneration++;
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadDrives() async {
    final generation = ++_navigationGeneration;
    setState(() {
      _loading = true;
      _addressError = null;
      _errorMessage = null;
    });
    try {
      final drives = await widget.driveRootsProvider();
      if (!mounted || generation != _navigationGeneration) return;
      setState(() {
        _entries = drives;
        _currentPath = null;
        _addressController.clear();
      });
    } on Object {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _errorMessage = '无法读取磁盘列表');
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadDirectory(
    String path, {
    bool preserveContentOnFailure = false,
  }) async {
    final generation = ++_navigationGeneration;
    setState(() {
      _loading = true;
      _addressError = null;
      _errorMessage = null;
    });
    try {
      final directories = await widget.directoryLoader(path);
      if (!mounted || generation != _navigationGeneration) return;
      setState(() {
        _entries = directories;
        _currentPath = path;
        _addressController.text = path;
      });
    } on Object {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() {
        if (preserveContentOnFailure) {
          _addressError = '目录不存在或无法访问';
        } else {
          _entries = <String>[];
          _currentPath = path;
          _addressController.text = path;
          _errorMessage = '无法读取该目录，移动硬盘可能已断开';
        }
      });
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitAddress() async {
    final path = normalizeLocalDirectoryAddress(_addressController.text);
    if (path.isEmpty) {
      await _loadDrives();
    } else {
      await _loadDirectory(path, preserveContentOnFailure: true);
    }
  }

  Future<void> _navigateUp() async {
    final currentPath = _currentPath;
    if (currentPath == null) return;
    final parent = p.dirname(currentPath);
    if (parent == currentPath || parent == '.') {
      await _loadDrives();
    } else {
      await _loadDirectory(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择本地文件夹'),
        actions: [
          TextButton.icon(
            key: const ValueKey<String>('select-current'),
            onPressed: _currentPath == null || _loading
                ? null
                : () => Navigator.of(context).pop(_currentPath),
            icon: const Icon(Icons.check),
            label: const Text('选择当前目录'),
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
                          _currentPath == null || _loading ? null : _navigateUp,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('local-directory-address'),
                        controller: _addressController,
                        enabled: !_loading,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _submitAddress(),
                        decoration: InputDecoration(
                          hintText: '输入文件夹地址',
                          prefixIcon:
                              const Icon(Icons.folder_outlined, size: 20),
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
                      key: const ValueKey('local-directory-go'),
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
            const Icon(Icons.usb_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadDrives,
              icon: const Icon(Icons.computer_outlined),
              label: const Text('返回磁盘列表'),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('当前目录没有子文件夹'));
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final path = _entries[index];
        final name = _currentPath == null ? path : p.basename(path);
        return ListTile(
          leading: Icon(
            _currentPath == null
                ? Icons.storage_outlined
                : Icons.folder_outlined,
          ),
          title: Text(name.isEmpty ? path : name),
          subtitle: _currentPath == null ? null : Text(path),
          onTap: () => _loadDirectory(path),
        );
      },
    );
  }
}

Future<List<String>> discoverWindowsDriveRoots() async {
  if (!Platform.isWindows) return <String>['/'];
  final drives = <String>[];
  for (var code = 'A'.codeUnitAt(0); code <= 'Z'.codeUnitAt(0); code++) {
    final root = '${String.fromCharCode(code)}:\\';
    try {
      if (await Directory(root).exists()) drives.add(root);
    } on FileSystemException {
      // 移动设备可能在枚举期间断开，忽略该盘符。
    }
  }
  return drives;
}

Future<List<String>> loadLocalDirectories(String path) async {
  final directories = <String>[];
  await for (final entry in Directory(path).list(followLinks: false)) {
    if (entry is Directory) directories.add(entry.path);
  }
  directories.sort((first, second) => p
      .basename(first)
      .toLowerCase()
      .compareTo(p.basename(second).toLowerCase()));
  return directories;
}
