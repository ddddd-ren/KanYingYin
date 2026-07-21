import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/baidu/baidu_directory_picker.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:url_launcher/url_launcher.dart';

typedef BaiduAuthorizationUrlLauncher = Future<bool> Function(Uri uri);

class BaiduSourceEditorPage extends StatefulWidget {
  const BaiduSourceEditorPage({
    super.key,
    this.source,
    this.controller,
    this.credentialStore,
    this.authorizationController,
    this.launchAuthorizationUrl,
    this.onRootSelectionChanged,
  });

  final CloudSource? source;
  final CloudLibraryController? controller;
  final CloudCredentialStore? credentialStore;
  final BaiduAuthorizationController? authorizationController;
  final BaiduAuthorizationUrlLauncher? launchAuthorizationUrl;
  final Future<void> Function(String sourceId)? onRootSelectionChanged;

  @override
  State<BaiduSourceEditorPage> createState() => _BaiduSourceEditorPageState();
}

class _BaiduSourceEditorPageState extends State<BaiduSourceEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  late final TextEditingController _authorizationCodeController;
  late final CloudLibraryController _controller;
  late final CloudCredentialStore _credentialStore;
  late final BaiduAuthorizationController _authorizationController;
  late final BaiduAuthorizationUrlLauncher _launchAuthorizationUrl;
  late final bool _ownsController;
  late final bool _ownsAuthorizationController;
  late final String _sourceId;
  late List<CloudRemoteRef> _rootRefs;
  CloudCredential? _existingCredential;
  CloudCredential? _authorizedCredential;
  bool _clientIdConfigured = false;
  bool _clientSecretConfigured = false;
  bool _loadingCredential = false;
  bool _updatingLibrary = false;
  bool _enabled = true;

  bool get _busy =>
      _controller.saving ||
      _controller.browsing ||
      _authorizationController.authorizing ||
      _loadingCredential ||
      _updatingLibrary;

  bool get _isAuthorized => _authorizedCredential != null;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudLibraryController();
    _credentialStore = widget.credentialStore ?? SecureCloudCredentialStore();
    _ownsAuthorizationController = widget.authorizationController == null;
    _authorizationController =
        widget.authorizationController ?? BaiduAuthorizationController();
    _launchAuthorizationUrl =
        widget.launchAuthorizationUrl ?? _launchInExternalBrowser;
    _controller.addListener(_refresh);
    _authorizationController.addListener(_refresh);
    _sourceId =
        widget.source?.id ?? 'baidu-${DateTime.now().microsecondsSinceEpoch}';
    _nameController = TextEditingController(
      text: widget.source?.name ?? '百度网盘',
    );
    _clientIdController = TextEditingController();
    _clientSecretController = TextEditingController();
    _authorizationCodeController = TextEditingController();
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
      final complete = _isCompleteCredential(credential) ? credential : null;
      setState(() {
        _existingCredential = credential;
        _authorizedCredential = complete;
        _clientIdConfigured = credential?.clientId?.trim().isNotEmpty == true;
        _clientSecretConfigured =
            credential?.clientSecret?.trim().isNotEmpty == true;
      });
    } on Object {
      if (mounted) _showMessage('已保存的百度凭据读取失败，请重新授权');
    } finally {
      if (mounted) setState(() => _loadingCredential = false);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _credentialsChanged() {
    _authorizationController.cancel();
    setState(() {
      _authorizedCredential = _formKeysMatchExisting()
          ? (_isCompleteCredential(_existingCredential)
              ? _existingCredential
              : null)
          : null;
    });
  }

  bool _formKeysMatchExisting() {
    final existing = _existingCredential;
    if (existing == null) return false;
    final clientId = _clientIdController.text.trim();
    final clientSecret = _clientSecretController.text.trim();
    return (clientId.isEmpty || clientId == existing.clientId?.trim()) &&
        (clientSecret.isEmpty || clientSecret == existing.clientSecret?.trim());
  }

  String get _effectiveClientId => _clientIdController.text.trim().isNotEmpty
      ? _clientIdController.text.trim()
      : (_existingCredential?.clientId?.trim() ?? '');

  String get _effectiveClientSecret =>
      _clientSecretController.text.trim().isNotEmpty
          ? _clientSecretController.text.trim()
          : (_existingCredential?.clientSecret?.trim() ?? '');

  CloudSource? _sourceFromForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return CloudSource(
      id: _sourceId,
      type: CloudSourceType.baidu,
      name: _nameController.text.trim(),
      baseUrl: 'https://pan.baidu.com',
      rootPaths: _rootRefs.map((reference) => reference.path).toList(),
      rootRefs: _rootRefs,
      enabled: _enabled,
      lastScannedAt: widget.source?.lastScannedAt,
      scanStatus: widget.source?.scanStatus ?? CloudScanStatus.never,
      indexedVideoCount: widget.source?.indexedVideoCount ?? 0,
      matchedSubtitleCount: widget.source?.matchedSubtitleCount ?? 0,
      lastScanFailureCount: widget.source?.lastScanFailureCount ?? 0,
    );
  }

  Future<void> _openAuthorization() async {
    final clientId = _effectiveClientId;
    final clientSecret = _effectiveClientSecret;
    if (clientId.isEmpty || clientSecret.isEmpty) {
      _showMessage('请先填写 API Key 和 Secret Key');
      return;
    }
    try {
      final uri = _authorizationController.begin(
        clientId: clientId,
        clientSecret: clientSecret,
      );
      if (!await _launchAuthorizationUrl(uri) && mounted) {
        _showMessage('无法打开系统浏览器，请复制授权地址后重试');
      }
    } on Object {
      if (mounted) {
        _showMessage(_authorizationController.errorMessage ?? '无法打开百度授权');
      }
    }
  }

  Future<void> _completeAuthorization() async {
    try {
      await _authorizationController.exchangeCode(
        _authorizationCodeController.text,
      );
      final credential = _authorizationController.authorizedCredential;
      if (!mounted || credential == null) return;
      setState(() {
        _existingCredential = credential;
        _authorizedCredential = credential;
        _clientIdConfigured = true;
        _clientSecretConfigured = true;
        _clientIdController.clear();
        _clientSecretController.clear();
        _authorizationCodeController.clear();
      });
      _showMessage('百度账号授权成功');
    } on Object {
      if (mounted) {
        _showMessage(_authorizationController.errorMessage ?? '百度账号授权失败');
      }
    }
  }

  Future<void> _chooseRoots() async {
    final source = _sourceFromForm();
    final credential = _authorizedCredential;
    if (source == null || credential == null) return;
    final selected = await Navigator.of(context).push<List<CloudRemoteRef>>(
      MaterialPageRoute(
        builder: (_) => BaiduDirectoryPickerPage(
          source: source,
          controller: _controller,
          credential: credential,
          initialSelection: _rootRefs,
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _rootRefs = selected);
  }

  Future<void> _save() async {
    final source = _sourceFromForm();
    final credential = _authorizedCredential;
    if (source == null) return;
    if (credential == null) {
      _showMessage('请先完成百度账号授权');
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
        if (mounted) {
          _showMessage('目录已保存，但媒体库更新失败，请稍后手动重试');
        }
        return;
      } finally {
        if (mounted) setState(() => _updatingLibrary = false);
      }
    }
    if (mounted) Navigator.of(context).maybePop();
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
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _authorizationCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _authorizationController.account;
    return Scaffold(
      appBar: AppBar(title: const Text('百度网盘数据源')),
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
                controller: _clientIdController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  helperText:
                      _clientIdConfigured ? 'API Key 已配置' : '请填写百度开放平台 API Key',
                ),
                onChanged: (_) => _credentialsChanged(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _clientSecretController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Secret Key',
                  helperText: _clientSecretConfigured
                      ? 'Secret Key 已配置'
                      : 'Secret Key 仅安全保存在本机',
                ),
                onChanged: (_) => _credentialsChanged(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openAuthorization,
                    icon: const Icon(Icons.open_in_browser_outlined),
                    label: const Text('打开百度授权'),
                  ),
                  if (account != null)
                    Text('已授权：${account.displayName}')
                  else if (_isAuthorized)
                    const Text('已授权，可选择媒体目录'),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _authorizationCodeController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '授权码',
                  helperText: '在百度授权页面完成授权后，将一次性授权码粘贴到这里',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed:
                      _busy || _authorizationController.authorizationUri == null
                          ? null
                          : _completeAuthorization,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(
                    _authorizationController.authorizing ? '正在授权' : '完成授权',
                  ),
                ),
              ),
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
                  OutlinedButton.icon(
                    onPressed: _busy || !_isAuthorized ? null : _chooseRoots,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('选择目录'),
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

  static bool _isCompleteCredential(CloudCredential? credential) =>
      credential?.clientId?.trim().isNotEmpty == true &&
      credential?.clientSecret?.trim().isNotEmpty == true &&
      credential?.accessToken?.trim().isNotEmpty == true &&
      credential?.refreshToken?.trim().isNotEmpty == true &&
      credential?.accessTokenExpiresAt != null;

  static Future<bool> _launchInExternalBrowser(Uri uri) => launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
}
