import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/openlist_directory_picker.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';

class OpenListSourceEditorPage extends StatefulWidget {
  const OpenListSourceEditorPage({
    super.key,
    this.source,
    this.controller,
    this.onRootSelectionChanged,
  });

  final CloudSource? source;
  final CloudLibraryController? controller;
  final Future<void> Function(String sourceId)? onRootSelectionChanged;

  @override
  State<OpenListSourceEditorPage> createState() =>
      _OpenListSourceEditorPageState();
}

class _OpenListSourceEditorPageState extends State<OpenListSourceEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final CloudLibraryController _controller;
  late final bool _ownsController;
  late final String _sourceId;
  late List<String> _rootPaths;
  bool _allowSelfSignedCertificate = false;
  bool _updatingLibrary = false;

  bool get _busy => _controller.saving || _updatingLibrary;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudLibraryController();
    _sourceId = widget.source?.id ??
        'openlist-${DateTime.now().microsecondsSinceEpoch}';
    _controller.addListener(_refresh);
    _nameController = TextEditingController(text: widget.source?.name ?? '');
    _urlController = TextEditingController(text: widget.source?.baseUrl ?? '');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _allowSelfSignedCertificate =
        widget.source?.allowSelfSignedCertificate ?? false;
    _rootPaths = List<String>.from(widget.source?.rootPaths ?? const ['/']);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  CloudSource? _sourceFromForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return CloudSource(
      id: _sourceId,
      type: CloudSourceType.openList,
      name: _nameController.text.trim(),
      baseUrl: _urlController.text.trim().replaceFirst(RegExp(r'/+$'), ''),
      rootPaths: _rootPaths,
      enabled: widget.source?.enabled ?? true,
      allowSelfSignedCertificate: _allowSelfSignedCertificate,
      lastScannedAt: widget.source?.lastScannedAt,
      scanStatus: widget.source?.scanStatus ?? CloudScanStatus.never,
      indexedVideoCount: widget.source?.indexedVideoCount ?? 0,
      matchedSubtitleCount: widget.source?.matchedSubtitleCount ?? 0,
      lastScanFailureCount: widget.source?.lastScanFailureCount ?? 0,
    );
  }

  CloudCredential get _credential => CloudCredential(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

  Future<void> _test() async {
    final source = _sourceFromForm();
    if (source == null) return;
    try {
      await _controller.testConnection(
        source: source,
        credential: _credential,
        allowSelfSignedCertificate: _allowSelfSignedCertificate,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OpenList 连接成功')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.errorMessage ?? '连接失败')),
      );
    }
  }

  Future<void> _save() async {
    final source = _sourceFromForm();
    if (source == null) return;
    final rootsChanged = CloudSourcePathScope.hasRootSelectionChanged(
      widget.source,
      source,
    );
    await _controller.save(
      source,
      credential:
          _usernameController.text.isEmpty && _passwordController.text.isEmpty
              ? null
              : _credential,
    );
    if (!mounted) return;
    if (rootsChanged && widget.onRootSelectionChanged != null) {
      setState(() => _updatingLibrary = true);
      try {
        await widget.onRootSelectionChanged!(source.id);
      } on Object {
        if (!mounted) return;
        _showMessage('目录已保存，但媒体库更新失败，请稍后手动重试');
        return;
      } finally {
        if (mounted) setState(() => _updatingLibrary = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _chooseDirectories() async {
    final source = _sourceFromForm();
    if (source == null) return;
    try {
      final formCredential =
          _usernameController.text.isEmpty && _passwordController.text.isEmpty
              ? null
              : _credential;
      final selected = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => OpenListDirectoryPickerPage(
            source: source,
            controller: _controller,
            credential: formCredential,
          ),
        ),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      setState(() => _rootPaths = selected);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.errorMessage ?? '扫描目录加载失败')),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    if (_ownsController) _controller.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OpenList 数据源')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '地址',
                hintText: 'https://drive.example.com',
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                final text = value?.trim() ?? '';
                final uri = Uri.tryParse(text);
                if (uri != null && uri.userInfo.isNotEmpty) {
                  return '地址不能包含用户名或密码';
                }
                try {
                  OpenListClient.normalizeBaseUrl(text);
                  return null;
                } on CloudDriveException catch (error) {
                  return error.type == CloudDriveErrorType.invalidAddress
                      ? '仅支持 HTTP 或 HTTPS 地址'
                      : '请填写完整地址';
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '密码',
                helperText: widget.source == null ? '密码仅安全保存在本机' : '留空将保留原密码',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许自签名证书'),
              subtitle: const Text('仅在你信任此 OpenList 服务器时开启'),
              value: _allowSelfSignedCertificate,
              onChanged: (value) =>
                  setState(() => _allowSelfSignedCertificate = value),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _controller.testing || _busy ? null : _test,
                  icon: const Icon(Icons.network_check_outlined),
                  label: Text(_controller.testing ? '正在测试' : '测试连接'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_updatingLibrary ? '正在更新媒体库' : '保存'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('扫描目录', style: TextStyle(fontSize: 16)),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy || _controller.browsing ? null : _chooseDirectories,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('选择扫描目录'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final path in _rootPaths)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(path),
              ),
          ],
        ),
      ),
    );
  }
}
