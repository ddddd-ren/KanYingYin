import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_directory_picker.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';

class QuarkSourceEditorPage extends StatefulWidget {
  const QuarkSourceEditorPage({
    super.key,
    this.source,
    this.controller,
    this.onRootSelectionChanged,
  });

  final CloudSource? source;
  final CloudLibraryController? controller;
  final Future<void> Function(String sourceId)? onRootSelectionChanged;

  @override
  State<QuarkSourceEditorPage> createState() => _QuarkSourceEditorPageState();
}

class _QuarkSourceEditorPageState extends State<QuarkSourceEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cookieController;
  late final CloudLibraryController _controller;
  late final bool _ownsController;
  late final String _sourceId;
  late List<CloudRemoteRef> _rootRefs;
  CloudRemoteRef? _defaultTransferDirectory;
  bool _enabled = true;
  String? _testedCookie;
  bool _updatingLibrary = false;

  bool get _busy => _controller.saving || _updatingLibrary;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudLibraryController();
    _controller.addListener(_refresh);
    _sourceId =
        widget.source?.id ?? 'quark-${DateTime.now().microsecondsSinceEpoch}';
    _nameController = TextEditingController(
      text: widget.source?.name ?? '夸克网盘',
    );
    // 安全要求：编辑时永不把已保存 Cookie 读回输入框。
    _cookieController = TextEditingController();
    _rootRefs = List<CloudRemoteRef>.from(
      widget.source?.remoteRoots ?? const <CloudRemoteRef>[],
    );
    _defaultTransferDirectory = widget.source?.defaultTransferDirectory;
    _enabled = widget.source?.enabled ?? true;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  CloudCredential? get _formCredential {
    final cookie = _cookieController.text.trim();
    return cookie.isEmpty ? null : CloudCredential(cookie: cookie);
  }

  CloudSource? _sourceFromForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return CloudSource(
      id: _sourceId,
      type: CloudSourceType.quark,
      name: _nameController.text.trim(),
      baseUrl: 'https://pan.quark.cn',
      rootPaths: _rootRefs.map((reference) => reference.path).toList(),
      rootRefs: _rootRefs,
      defaultTransferDirectory: _defaultTransferDirectory,
      enabled: _enabled,
      lastScannedAt: widget.source?.lastScannedAt,
      scanStatus: widget.source?.scanStatus ?? CloudScanStatus.never,
      indexedVideoCount: widget.source?.indexedVideoCount ?? 0,
      matchedSubtitleCount: widget.source?.matchedSubtitleCount ?? 0,
      lastScanFailureCount: widget.source?.lastScanFailureCount ?? 0,
    );
  }

  Future<void> _test() async {
    final source = _sourceFromForm();
    if (source == null) return;
    try {
      await _controller.testConnection(
        source: source,
        credential: _formCredential ?? const CloudCredential(),
        allowSelfSignedCertificate: false,
      );
      _testedCookie = _cookieController.text.trim();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('夸克账号验证成功')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.errorMessage ?? '夸克账号验证失败')),
      );
    }
  }

  Future<void> _save() async {
    final source = _sourceFromForm();
    if (source == null) return;
    final cookie = _cookieController.text.trim();
    if (widget.source == null && cookie.isEmpty) {
      _showMessage('请粘贴 Cookie 并先测试登录');
      return;
    }
    if (cookie.isNotEmpty && _testedCookie != cookie) {
      _showMessage('新 Cookie 必须先通过测试登录');
      return;
    }
    final rootsChanged = CloudSourcePathScope.hasRootSelectionChanged(
      widget.source,
      source,
    );
    await _controller.save(source, credential: _formCredential);
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
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _chooseRoots() async {
    final source = _sourceFromForm();
    if (source == null) return;
    final selected = await Navigator.of(context).push<List<CloudRemoteRef>>(
      MaterialPageRoute(
        builder: (_) => QuarkDirectoryPickerPage(
          source: source,
          controller: _controller,
          credential: _formCredential,
          initialSelection: _rootRefs,
          title: '选择媒体根目录',
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _rootRefs = selected);
  }

  Future<void> _chooseTransferDirectory() async {
    final source = _sourceFromForm();
    if (source == null) return;
    final selected = await Navigator.of(context).push<List<CloudRemoteRef>>(
      MaterialPageRoute(
        builder: (_) => QuarkDirectoryPickerPage(
          source: source,
          controller: _controller,
          credential: _formCredential,
          initialSelection: <CloudRemoteRef>[
            if (_defaultTransferDirectory != null) _defaultTransferDirectory!,
          ],
          singleSelection: true,
          title: '选择默认转存目录',
        ),
      ),
    );
    if (mounted && selected?.isNotEmpty == true) {
      setState(() => _defaultTransferDirectory = selected!.single);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    if (_ownsController) _controller.dispose();
    _nameController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('夸克网盘数据源')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '来源名称'),
              validator: (value) =>
                  value?.trim().isEmpty == true ? '请填写来源名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cookieController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Cookie',
                helperText: widget.source == null
                    ? '仅安全保存在 Windows 凭据存储中'
                    : '留空保留原 Cookie；输入新值后需重新测试',
              ),
              onChanged: (_) => _testedCookie = null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用此来源'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 16),
            _DirectorySection(
              title: '媒体根目录',
              value: _rootRefs.isEmpty
                  ? '尚未选择'
                  : _rootRefs.map((reference) => reference.path).join('、'),
              buttonLabel: '选择目录',
              onPressed: _busy || _controller.browsing ? null : _chooseRoots,
            ),
            const SizedBox(height: 16),
            _DirectorySection(
              title: '默认转存目录',
              value: _defaultTransferDirectory?.path ?? '尚未选择',
              buttonLabel: '选择目录',
              onPressed: _busy || _controller.browsing
                  ? null
                  : _chooseTransferDirectory,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _controller.testing || _busy ? null : _test,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(_controller.testing ? '正在测试' : '测试登录'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_updatingLibrary ? '正在更新媒体库' : '保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectorySection extends StatelessWidget {
  const _DirectorySection({
    required this.title,
    required this.value,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String value;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(buttonLabel),
          ),
        ],
      );
}
