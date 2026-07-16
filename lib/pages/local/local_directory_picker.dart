import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

typedef LocalDriveRootsProvider = Future<List<String>> Function();
typedef LocalDirectoryLoader = Future<List<String>> Function(String path);

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
  List<String> _entries = <String>[];
  String? _currentPath;
  String? _errorMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialPath = widget.initialPath?.trim() ?? '';
      if (initialPath.isEmpty) {
        _loadDrives();
      } else {
        _loadDirectory(initialPath);
      }
    });
  }

  Future<void> _loadDrives() async {
    setState(() {
      _loading = true;
      _currentPath = null;
      _errorMessage = null;
    });
    try {
      final drives = await widget.driveRootsProvider();
      if (!mounted) return;
      setState(() => _entries = drives);
    } on Object {
      if (!mounted) return;
      setState(() => _errorMessage = '无法读取磁盘列表');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _currentPath = path;
      _errorMessage = null;
    });
    try {
      final directories = await widget.directoryLoader(path);
      if (!mounted) return;
      setState(() => _entries = directories);
    } on Object {
      if (!mounted) return;
      setState(() {
        _entries = <String>[];
        _errorMessage = '无法读取该目录，移动硬盘可能已断开';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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
          ListTile(
            leading: IconButton(
              tooltip: '上级目录',
              onPressed: _currentPath == null || _loading ? null : _navigateUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            title: Text(
              _currentPath ?? '此电脑',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
