import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_directory_picker.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_verification_dialog.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_client_configuration.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

class XunleiSourceEditorPage extends StatefulWidget {
  const XunleiSourceEditorPage({
    super.key,
    this.source,
    this.controller,
    this.credentialStore,
    this.authorizationController,
    this.configuration = const XunleiClientConfiguration(),
    this.verificationDialogLauncher,
    this.onRootSelectionChanged,
  });

  final CloudSource? source;
  final CloudLibraryController? controller;
  final CloudCredentialStore? credentialStore;
  final XunleiAuthorizationController? authorizationController;
  final XunleiClientConfiguration configuration;
  final XunleiVerificationDialogLauncher? verificationDialogLauncher;
  final Future<void> Function(String sourceId)? onRootSelectionChanged;

  @override
  State<XunleiSourceEditorPage> createState() => _XunleiSourceEditorPageState();
}

class _XunleiSourceEditorPageState extends State<XunleiSourceEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _refreshTokenController;
  late final TextEditingController _identifierController;
  late final TextEditingController _passwordController;
  late final FocusNode _passwordFocusNode;
  late final CloudLibraryController _controller;
  late final CloudCredentialStore _credentialStore;
  late final XunleiAuthorizationController _authorizationController;
  late final XunleiVerificationDialogLauncher _verificationDialogLauncher;
  late final bool _ownsController;
  late final bool _ownsAuthorizationController;
  late final String _sourceId;
  late List<CloudRemoteRef> _rootRefs;
  CloudCredential? _authorizedCredential;
  bool _loadingCredential = false;
  bool _updatingLibrary = false;
  bool _enabled = true;
  bool _showRefreshToken = false;
  String? _passwordErrorText;

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

  bool get _authorizationAvailable =>
      widget.authorizationController != null ||
      widget.configuration.isConfigured;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudLibraryController();
    _credentialStore = widget.credentialStore ?? SecureCloudCredentialStore();
    _ownsAuthorizationController = widget.authorizationController == null;
    _authorizationController = widget.authorizationController ??
        XunleiAuthorizationController(
          policy: XunleiRequestPolicy(configuration: widget.configuration),
        );
    _verificationDialogLauncher =
        widget.verificationDialogLauncher ?? showXunleiVerificationDialog;
    _controller.addListener(_refresh);
    _authorizationController.addListener(_refresh);
    _sourceId =
        widget.source?.id ?? 'xunlei-${DateTime.now().microsecondsSinceEpoch}';
    _nameController = TextEditingController(
      text: widget.source?.name ?? '迅雷网盘',
    );
    _refreshTokenController = TextEditingController();
    _identifierController = TextEditingController();
    _passwordController = TextEditingController();
    _passwordFocusNode = FocusNode();
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
    if (_passwordErrorText != null) {
      setState(() => _passwordErrorText = null);
    }
    try {
      await _authorizationController.login(
        identifier: identifier,
        password: password,
      );
      _acceptAuthorizedCredential();
    } on XunleiVerificationRequired {
      await _runVerification();
    } on CloudDriveException catch (error) {
      if (!mounted) return;
      if (error.type == CloudDriveErrorType.invalidPassword) {
        setState(() => _passwordErrorText = '迅雷密码错误，请重新输入');
        _passwordController.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _passwordFocusNode.requestFocus();
        });
      } else {
        _showMessage(_authorizationController.errorMessage ?? '迅雷登录失败');
      }
    } on Object {
      if (mounted) {
        _showMessage(_authorizationController.errorMessage ?? '迅雷登录失败');
      }
    } finally {
      if (mounted) _passwordController.clear();
    }
  }

  Future<void> _runVerification() async {
    final challenge = _authorizationController.verificationChallenge;
    if (!mounted) return;
    if (challenge == null) {
      _showMessage('迅雷设备验证失败，请重新登录');
      return;
    }
    XunleiVerificationDialogResult result;
    try {
      result = await _verificationDialogLauncher(context, challenge);
    } on Object {
      if (!mounted) return;
      const message = '迅雷设备验证失败，请重新登录';
      _authorizationController.failVerification(message);
      _showMessage(message);
      return;
    }
    if (!mounted) return;
    switch (result.outcome) {
      case XunleiVerificationDialogOutcome.verified:
        try {
          await _authorizationController.completeVerification(
            creditKey: result.creditKey ?? '',
          );
          _acceptAuthorizedCredential();
        } on Object {
          if (mounted) {
            _showMessage(
              _authorizationController.errorMessage ?? '迅雷设备验证失败，请重新登录',
            );
          }
        }
      case XunleiVerificationDialogOutcome.cancelled:
        _authorizationController.cancelVerification();
      case XunleiVerificationDialogOutcome.failed:
        final message = result.errorMessage ?? '迅雷设备验证失败，请重新登录';
        _authorizationController.failVerification(message);
        _showMessage(message);
    }
  }

  Future<void> _authorizeWithRefreshToken() async {
    final refreshToken = _refreshTokenController.text.trim();
    if (refreshToken.isEmpty) {
      _showMessage('请填写 Refresh Token');
      return;
    }
    try {
      await _authorizationController.authorizeWithRefreshToken(
        refreshToken: refreshToken,
        deviceId: _authorizedCredential?.deviceId,
      );
      _acceptAuthorizedCredential();
    } on Object {
      if (mounted) {
        _showMessage(_authorizationController.errorMessage ?? '迅雷授权失败');
      }
    } finally {
      if (mounted) _refreshTokenController.clear();
    }
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
          onCredentialRefreshed: _acceptRefreshedCredential,
          initialSelection: _rootRefs,
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _rootRefs = selected);
  }

  void _acceptRefreshedCredential(CloudCredential credential) {
    if (!mounted || !_isCompleteCredential(credential)) return;
    setState(() => _authorizedCredential = credential);
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
    _refreshTokenController.dispose();
    _identifierController.dispose();
    _passwordFocusNode.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  List<Widget> _buildCompatibleLogin() => <Widget>[
        TextFormField(
          key: const ValueKey<String>('xunlei-identifier'),
          controller: _identifierController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '迅雷账号',
            helperText: '支持手机号或迅雷账号',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey<String>('xunlei-password'),
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '迅雷密码',
            helperText: '密码仅用于本次兼容登录，不会保存',
            errorText: _passwordErrorText,
          ),
          onChanged: (_) {
            if (_passwordErrorText != null) {
              setState(() => _passwordErrorText = null);
            }
          },
          onFieldSubmitted:
              !_authorizationAvailable ? null : (_) => _busy ? null : _login(),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy || !_authorizationAvailable ? null : _login,
            icon: const Icon(Icons.login_outlined),
            label: Text(_authorizationBusy ? '正在登录' : '兼容登录'),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final accountLabel = _authorizedCredential?.accountLabel?.trim();
    return KSettingsScaffold(
      title: '迅雷网盘数据源',
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (!_authorizationAvailable) ...<Widget>[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    XunleiClientConfiguration.missingConfigurationMessage,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '来源名称'),
                validator: (value) =>
                    value?.trim().isEmpty == true ? '请填写来源名称' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('xunlei-refresh-token'),
                controller: _refreshTokenController,
                obscureText: !_showRefreshToken,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Refresh Token',
                  helperText: _isAuthorized
                      ? '已授权；如需更换账号，请粘贴新的 Token'
                      : '网页 Refresh Token 可能绑定原浏览器设备；'
                          '目录读取失败时请改用下方账号密码登录',
                  suffixIcon: IconButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                              () => _showRefreshToken = !_showRefreshToken,
                            ),
                    icon: Icon(
                      _showRefreshToken
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                onFieldSubmitted: !_authorizationAvailable
                    ? null
                    : (_) => _busy ? null : _authorizeWithRefreshToken(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _busy || !_authorizationAvailable
                        ? null
                        : _authorizeWithRefreshToken,
                    icon: const Icon(Icons.key_outlined),
                    label: Text(
                      _authorizationBusy
                          ? '正在验证'
                          : _isAuthorized
                              ? '重新授权'
                              : '验证并登录',
                    ),
                  ),
                  if (_isAuthorized)
                    Text(
                      accountLabel == null || accountLabel.isEmpty
                          ? '登录成功'
                          : '登录成功：$accountLabel',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                key: const ValueKey<String>('xunlei-compatible-login'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 16),
                title: const Text('账号密码兼容登录'),
                subtitle: const Text(
                  '推荐使用账号密码登录，以当前设备身份读取迅雷目录',
                ),
                children: _buildCompatibleLogin(),
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
}
