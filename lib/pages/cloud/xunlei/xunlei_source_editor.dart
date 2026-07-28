import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_directory_picker.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:url_launcher/url_launcher.dart';

typedef XunleiVerificationUrlLauncher = Future<bool> Function(Uri uri);

class XunleiSourceEditorPage extends StatefulWidget {
  const XunleiSourceEditorPage({
    super.key,
    this.source,
    this.controller,
    this.credentialStore,
    this.authorizationController,
    this.launchVerificationUrl,
    this.onRootSelectionChanged,
  });

  final CloudSource? source;
  final CloudLibraryController? controller;
  final CloudCredentialStore? credentialStore;
  final XunleiAuthorizationController? authorizationController;
  final XunleiVerificationUrlLauncher? launchVerificationUrl;
  final Future<void> Function(String sourceId)? onRootSelectionChanged;

  @override
  State<XunleiSourceEditorPage> createState() => _XunleiSourceEditorPageState();
}

class _XunleiSourceEditorPageState extends State<XunleiSourceEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _identifierController;
  late final TextEditingController _passwordController;
  late final CloudLibraryController _controller;
  late final CloudCredentialStore _credentialStore;
  late final XunleiAuthorizationController _authorizationController;
  late final XunleiVerificationUrlLauncher _launchVerificationUrl;
  late final bool _ownsController;
  late final bool _ownsAuthorizationController;
  late final String _sourceId;
  late List<CloudRemoteRef> _rootRefs;
  CloudCredential? _authorizedCredential;
  bool _loadingCredential = false;
  bool _updatingLibrary = false;
  bool _enabled = true;

  bool get _authorizationBusy =>
      _authorizationController.state == XunleiAuthorizationState.signingIn ||
      _authorizationController.state == XunleiAuthorizationState.verifying;

  bool get _busy =>
      _controller.saving ||
      _controller.browsing ||
      _authorizationBusy ||
      _loadingCredential ||
      _updatingLibrary;

  bool get _isAuthorized => _isCompleteCredential(_authorizedCredential);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudLibraryController();
    _credentialStore = widget.credentialStore ?? SecureCloudCredentialStore();
    _ownsAuthorizationController = widget.authorizationController == null;
    _authorizationController =
        widget.authorizationController ?? XunleiAuthorizationController();
    _launchVerificationUrl =
        widget.launchVerificationUrl ?? _launchInExternalBrowser;
    _controller.addListener(_refresh);
    _authorizationController.addListener(_refresh);
    _sourceId =
        widget.source?.id ?? 'xunlei-${DateTime.now().microsecondsSinceEpoch}';
    _nameController = TextEditingController(
      text: widget.source?.name ?? '迅雷网盘',
    );
    _identifierController = TextEditingController();
    _passwordController = TextEditingController();
    _rootRefs = List<CloudRemoteRef>.from(
      widget.source?.remoteRoots ?? const <CloudRemoteRef>[],
    );
    _enabled = widget.source?.enabled ?? true;
    if (widget.source != null) _loadExistingCredential();
  }

  Future<void> _loadExistingCredential() async {
    setState(() => _loadingCredential = true);
    try {
      final credential = await _credentialStore.read(_sourceId);
      if (!mounted) return;
      setState(() {
        _authorizedCredential =
            _isCompleteCredential(credential) ? credential : null;
      });
    } on Object {
      if (mounted) _showMessage('已保存的迅雷凭据读取失败，请重新登录');
    } finally {
      if (mounted) setState(() => _loadingCredential = false);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      _showMessage('请填写迅雷账号和密码');
      return;
    }
    try {
      await _authorizationController.login(
        identifier: identifier,
        password: password,
      );
      _acceptAuthorizedCredential();
    } on XunleiVerificationRequired {
      final uri = _authorizationController.verificationUri;
      if (uri == null) {
        _showMessage('迅雷验证地址无效');
        return;
      }
      try {
        if (!await _launchVerificationUrl(uri) && mounted) {
          _showMessage('无法打开系统浏览器，请重试');
        }
      } on Object {
        if (mounted) _showMessage('无法打开系统浏览器，请重试');
      }
    } on Object {
      if (mounted) {
        _showMessage(_authorizationController.errorMessage ?? '迅雷登录失败');
      }
    } finally {
      if (mounted) _passwordController.clear();
    }
  }

  Future<void> _openVerification() async {
    final uri = _authorizationController.verificationUri;
    if (uri == null) return;
    try {
      if (!await _launchVerificationUrl(uri) && mounted) {
        _showMessage('无法打开系统浏览器，请重试');
      }
    } on Object {
      if (mounted) _showMessage('无法打开系统浏览器，请重试');
    }
  }

  Future<void> _completeVerification() async {
    try {
      await _authorizationController.completeVerification();
      _acceptAuthorizedCredential();
    } on Object {
      if (mounted) {
        _showMessage(
          _authorizationController.errorMessage ?? '迅雷设备验证失败',
        );
      }
    } finally {
      if (mounted) _passwordController.clear();
    }
  }

  void _cancelVerification() {
    _authorizationController.cancelVerification();
    _passwordController.clear();
  }

  void _acceptAuthorizedCredential() {
    final credential = _authorizationController.authorizedCredential;
    if (!mounted || !_isCompleteCredential(credential)) return;
    setState(() => _authorizedCredential = credential);
    _showMessage('登录成功');
  }

  CloudSource? _sourceFromForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return CloudSource(
      id: _sourceId,
      type: CloudSourceType.xunlei,
      name: _nameController.text.trim(),
      baseUrl: 'https://pan.xunlei.com',
      rootPaths:
          _rootRefs.map((reference) => reference.path).toList(growable: false),
      rootRefs: _rootRefs,
      enabled: _enabled,
      lastScannedAt: widget.source?.lastScannedAt,
      scanStatus: widget.source?.scanStatus ?? CloudScanStatus.never,
      indexedVideoCount: widget.source?.indexedVideoCount ?? 0,
      matchedSubtitleCount: widget.source?.matchedSubtitleCount ?? 0,
      lastScanFailureCount: widget.source?.lastScanFailureCount ?? 0,
    );
  }

  Future<void> _chooseRoots() async {
    final source = _sourceFromForm();
    final credential = _authorizedCredential;
    if (source == null || credential == null) return;
    final selected = await Navigator.of(context).push<List<CloudRemoteRef>>(
      MaterialPageRoute(
        builder: (_) => XunleiDirectoryPickerPage(
          source: source,
          controller: _controller,
          credential: credential,
          initialSelection: _rootRefs,
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _rootRefs = selected);
  }

  void _clearRoots() {
    if (_rootRefs.isEmpty) return;
    setState(_rootRefs.clear);
  }

  Future<void> _save() async {
    final source = _sourceFromForm();
    final credential = _authorizedCredential;
    if (source == null) return;
    if (!_isCompleteCredential(credential)) {
      _showMessage('请先完成迅雷账号登录');
      return;
    }
    if (_rootRefs.isEmpty) {
      _showMessage('请至少选择一个媒体根目录');
      return;
    }
    final rootsChanged = CloudSourcePathScope.hasRootSelectionChanged(
      widget.source,
      source,
    );
    await _controller.save(source, credential: credential);
    if (!mounted) return;
    if (rootsChanged && widget.onRootSelectionChanged != null) {
      setState(() => _updatingLibrary = true);
      try {
        await widget.onRootSelectionChanged!(source.id);
      } on Object {
        if (mounted) _showMessage('目录已保存，但媒体库更新失败，请稍后重试');
        return;
      } finally {
        if (mounted) setState(() => _updatingLibrary = false);
      }
    }
    if (mounted) Navigator.of(context).pop(source.id);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _authorizationController.removeListener(_refresh);
    if (_ownsController) _controller.dispose();
    if (_ownsAuthorizationController) _authorizationController.dispose();
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verifying = _authorizationController.state ==
        XunleiAuthorizationState.verificationRequired;
    final accountLabel = _authorizedCredential?.accountLabel?.trim();
    return KSettingsScaffold(
      title: '迅雷网盘数据源',
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '来源名称'),
                validator: (value) =>
                    value?.trim().isEmpty == true ? '请填写来源名称' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('xunlei-identifier'),
                controller: _identifierController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '迅雷账号',
                  helperText: _isAuthorized ? '已授权，无需重新输入账号' : '支持手机号或迅雷账号',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('xunlei-password'),
                controller: _passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '迅雷密码',
                  helperText: '密码仅用于本次登录，不会保存',
                ),
                onFieldSubmitted: (_) => _busy ? null : _login(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: const Icon(Icons.login_outlined),
                    label: Text(_authorizationBusy ? '正在登录' : '登录迅雷'),
                  ),
                  if (_isAuthorized)
                    Text(
                      accountLabel == null || accountLabel.isEmpty
                          ? '登录成功'
                          : '登录成功：$accountLabel',
                    ),
                ],
              ),
              if (verifying) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('请在系统浏览器中完成迅雷设备验证'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _openVerification,
                              icon: const Icon(Icons.open_in_browser_outlined),
                              label: const Text('打开验证页面'),
                            ),
                            FilledButton.icon(
                              onPressed: _busy ? null : _completeVerification,
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('完成验证'),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _cancelVerification,
                              child: const Text('取消验证'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用此来源'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('媒体根目录', style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          _rootRefs.isEmpty
                              ? '尚未选择'
                              : _rootRefs
                                  .map((reference) => reference.path)
                                  .join('、'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey<String>('clear-cloud-media-roots'),
                    onPressed: _busy || _rootRefs.isEmpty ? null : _clearRoots,
                    icon: const Icon(Icons.clear_all_rounded),
                    label: const Text('清除'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy || !_isAuthorized ? null : _chooseRoots,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('选择媒体目录'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy || !_isAuthorized ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_updatingLibrary ? '正在更新媒体库' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isCompleteCredential(CloudCredential? credential) {
    final refreshToken = credential?.refreshToken?.trim() ?? '';
    final deviceId = credential?.deviceId?.trim() ?? '';
    return refreshToken.isNotEmpty &&
        RegExp(r'^[0-9a-f]{32}$').hasMatch(deviceId);
  }

  static Future<bool> _launchInExternalBrowser(Uri uri) => launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
}
