import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_credentials.dart';

class TmdbSettingsPage extends StatefulWidget {
  const TmdbSettingsPage({
    super.key,
    required this.credentialManager,
    required this.settings,
    this.apiKeyProvider,
    this.visionCredentials,
    this.visionOnly = false,
    this.onVisionSettingsSaved,
  });

  final TmdbCredentialManager credentialManager;
  final TypedSettings settings;
  final TmdbApiKeyProvider? apiKeyProvider;
  final TmdbVisionModelCredentialStore? visionCredentials;
  final bool visionOnly;
  final Future<void> Function()? onVisionSettingsSaved;

  @override
  State<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends State<TmdbSettingsPage> {
  static const _autoScrapeSetting = 'tmdbAutoScrape';
  late final TextEditingController _apiKeyController;
  late final TextEditingController _visionBaseUrlController;
  late final TextEditingController _visionModelController;
  late final TextEditingController _visionApiKeyController;
  bool _autoScrape = true;
  bool _obscureApiKey = true;
  bool _testing = false;
  bool _testingVision = false;
  bool _visionEnabled = false;
  bool _visionAutoClassification = false;
  bool _obscureVisionKey = true;
  bool _visionKeyChanged = false;
  late final TmdbVisionModelCredentialStore _visionCredentials =
      widget.visionCredentials ?? MemoryTmdbVisionModelCredentials();
  bool _visionKeyLoaded = false;
  final TmdbVisionModelClient _visionClient = TmdbVisionModelClient();
  late final TmdbApiKeyProvider _apiKeyProvider;
  late TmdbScrapeOptions _options;
  TypedSettings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _apiKeyProvider = widget.apiKeyProvider ??
        TmdbApiKeyProvider(userKeyReader: widget.credentialManager.read);
    _apiKeyController = TextEditingController(
      text: widget.credentialManager.read(),
    );
    final visionConfig = TmdbVisionModelConfig.fromMap(
      _settings.get('tmdbVisionModel'),
    );
    _visionEnabled = visionConfig.enabled;
    _visionAutoClassification = visionConfig.autoClassification;
    _visionBaseUrlController =
        TextEditingController(text: visionConfig.baseUrl);
    _visionModelController = TextEditingController(text: visionConfig.model);
    _visionApiKeyController = TextEditingController();
    _loadVisionKey();
    _autoScrape = _settings.getTyped<bool>(
      _autoScrapeSetting,
      defaultValue: true,
    );
    _options = TmdbScrapeOptions.fromMap(
      _settings.get('tmdbScrapeOptions'),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _visionBaseUrlController.dispose();
    _visionModelController.dispose();
    _visionApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var message = widget.visionOnly ? 'AI 设置已保存' : 'TMDB 设置已保存';
    try {
      final before = _settings.get('tmdbVisionModel');
      final next = _visionConfig(enabled: _visionEnabled).toMap();
      final changed =
          before is! Map || !mapEquals(before, next) || _visionKeyChanged;
      if (!widget.visionOnly) {
        await widget.credentialManager.save(_apiKeyController.text);
        await _settings.put(_autoScrapeSetting, _autoScrape);
        await _settings.put('tmdbScrapeOptions', _options.toMap());
      }
      await _settings.put(
        'tmdbVisionModel',
        _visionConfig(enabled: _visionEnabled).toMap(),
      );
      if (_visionKeyLoaded || _visionKeyChanged) {
        await _visionCredentials.save(_visionApiKeyController.text);
      }
      if (changed) {
        try {
          await widget.onVisionSettingsSaved?.call();
        } on Object {
          message = '设置已保存，自动重试未能启动，请刷新媒体库';
          TmdbVisionModelClient.report(message);
        }
      }
      _visionKeyChanged = false;
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置或凭据保存失败，请稍后重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  TmdbVisionModelConfig _visionConfig({required bool enabled}) =>
      TmdbVisionModelConfig(
        enabled: enabled,
        baseUrl: _visionBaseUrlController.text.trim(),
        model: _visionModelController.text.trim(),
        autoClassification: _visionAutoClassification,
      );

  Future<void> _loadVisionKey() async {
    try {
      final key = await _visionCredentials.read();
      if (!mounted) return;
      _visionKeyLoaded = true;
      if (_visionApiKeyController.text.isEmpty) {
        _visionApiKeyController.text = key;
      }
    } on Object {
      _visionKeyLoaded = false;
    }
  }

  Future<void> _testVisionConnection() async {
    final config = _visionConfig(enabled: true);
    final key = _visionApiKeyController.text.trim().isNotEmpty
        ? _visionApiKeyController.text.trim()
        : await _visionCredentials.read();
    if (!mounted) return;
    if (!config.isConfigured || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写有效的兼容接口地址、模型名称和 API Key')),
      );
      return;
    }
    setState(() => _testingVision = true);
    final connected = await _visionClient.testConnection(
      config: config,
      apiKey: key,
    );
    if (!mounted) return;
    setState(() => _testingVision = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            connected ? '识别接口与结果解析验证成功' : TmdbVisionModelClient.activity.value),
      ),
    );
  }

  Future<void> _testConnection() async {
    final inputKey = _apiKeyController.text.trim();
    final key = inputKey.isNotEmpty ? inputKey : _apiKeyProvider.read();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 TMDB API Key')),
      );
      return;
    }
    setState(() => _testing = true);
    try {
      await TmdbClient(apiKey: key).search('Avatar', TmdbMediaType.movie);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB 连接成功')),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final invalidCredential = error.response?.statusCode == 401;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(invalidCredential
              ? 'TMDB 凭据无效，请填写 v3 API Key 或 v4 读取访问令牌'
              : 'TMDB 连接失败，请检查网络连接'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB 连接失败，请检查填写内容')),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearMetadataCache() async {
    await _settings.delete('tmdbMetadataCache');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('TMDB 元数据缓存已清理')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KSettingsScaffold(
      title: widget.visionOnly ? 'AI 识别与分类' : 'TMDB 刮削设置',
      description: widget.visionOnly
          ? '配置兼容接口、模型和安全存储的 API Key。'
          : '管理海报与影片资料的凭据、语言和覆盖规则。',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!widget.visionOnly) ...[
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'TMDB API Key',
                helperText: '密钥仅保存在看影音专属安全存储，用于获取海报和影片信息',
                suffixIcon: IconButton(
                  tooltip: _obscureApiKey ? '显示密钥' : '隐藏密钥',
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '公共安装包不内置 TMDB Key。没有 Key 或断网时，本地扫描和播放仍可用；不会修改或删除原始视频、字幕。',
              key: ValueKey<String>('tmdb-zero-config-notice'),
            ),
            const SizedBox(height: 8),
            Text(
              _apiKeySourceLabel,
              key: const ValueKey<String>('tmdb-key-source'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('扫描后自动刮削'),
              subtitle: const Text('没有密钥或网络不可用时不会影响本地扫描和播放'),
              value: _autoScrape,
              onChanged: (value) => setState(() => _autoScrape = value),
            ),
            Text('刮削选项', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _options.language,
              decoration: const InputDecoration(labelText: '首选语言'),
              items: const [
                DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
                DropdownMenuItem(value: 'zh-TW', child: Text('繁体中文')),
                DropdownMenuItem(value: 'en-US', child: Text('英语')),
                DropdownMenuItem(value: 'ja-JP', child: Text('日语')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _options = _options.copyWith(language: value));
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TmdbMediaTypeMode>(
              initialValue: _options.mediaTypeMode,
              decoration: const InputDecoration(labelText: '默认媒体类型'),
              items: const [
                DropdownMenuItem(
                    value: TmdbMediaTypeMode.auto, child: Text('自动判断')),
                DropdownMenuItem(
                    value: TmdbMediaTypeMode.movie, child: Text('电影')),
                DropdownMenuItem(
                    value: TmdbMediaTypeMode.tv, child: Text('电视剧')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(
                      () => _options = _options.copyWith(mediaTypeMode: value));
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TmdbConfidenceMode>(
              initialValue: _options.confidenceMode,
              decoration: const InputDecoration(labelText: '自动匹配置信度'),
              items: const [
                DropdownMenuItem(
                    value: TmdbConfidenceMode.strict, child: Text('保守')),
                DropdownMenuItem(
                    value: TmdbConfidenceMode.standard, child: Text('标准')),
                DropdownMenuItem(
                    value: TmdbConfidenceMode.relaxed, child: Text('宽松')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() =>
                      _options = _options.copyWith(confidenceMode: value));
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('覆盖已有标题'),
              value: _options.overwriteTitle,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(overwriteTitle: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('覆盖已有简介'),
              value: _options.overwriteOverview,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(overwriteOverview: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('覆盖已有海报'),
              value: _options.overwritePoster,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(overwritePoster: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('刮削剧集名称'),
              subtitle: const Text('显示 TMDB 返回的每集名称'),
              value: _options.scrapeEpisodeNames,
              onChanged: (value) => setState(() =>
                  _options = _options.copyWith(scrapeEpisodeNames: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('获取海报'),
              value: _options.fetchPoster,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(fetchPoster: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('获取背景图'),
              value: _options.fetchBackdrop,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(fetchBackdrop: value)),
            ),
            const Divider(height: 32),
            KSettingsTile<void>.navigation(
              key: const ValueKey<String>('tmdb-test-connection'),
              leading: const Icon(Icons.network_check_outlined),
              title: const Text('测试 TMDB 连接'),
              description: const Text('验证当前密钥和网络是否可用'),
              enabled: !_testing,
              value: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onPressed: (_) => _testConnection(),
            ),
            KSettingsTile<void>.navigation(
              key: const ValueKey<String>('tmdb-clear-cache'),
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清理元数据缓存'),
              description: const Text('不会删除媒体文件或已经写入媒体库的信息'),
              onPressed: (_) => _clearMetadataCache(),
            ),
            const Divider(height: 32),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('AI 识别与分类', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 AI 剧名识别'),
                subtitle: const Text('网盘刮削失败时自动识别原始文件资料，并校验 TMDB 候选；本地可使用缩小画面'),
                value: _visionEnabled,
                onChanged: (value) => setState(() => _visionEnabled = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 AI 自动分类'),
                subtitle: const Text('刮削后自动补充不明确的主分类；人工选择优先，全手动模式不自动应用'),
                value: _visionAutoClassification,
                onChanged: (value) =>
                    setState(() => _visionAutoClassification = value),
              ),
              TextField(
                controller: _visionBaseUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '兼容接口地址',
                  helperText:
                      'OpenAI Chat Completions 兼容地址，如 https://api.example.com/v1；本机服务可用 localhost',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _visionModelController,
                decoration: const InputDecoration(labelText: '多模态模型名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _visionApiKeyController,
                obscureText: _obscureVisionKey,
                onChanged: (_) => _visionKeyChanged = true,
                decoration: InputDecoration(
                  labelText: '模型 API Key',
                  helperText: '密钥只保存在看影音安全存储，不会进入配置迁移和日志',
                  suffixIcon: IconButton(
                    tooltip: _obscureVisionKey ? '显示密钥' : '隐藏密钥',
                    onPressed: () =>
                        setState(() => _obscureVisionKey = !_obscureVisionKey),
                    icon: Icon(
                      _obscureVisionKey
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '识别时会将原始文件名、相关目录及必要的缩小画面发送给你配置的模型服务商；分类使用 TMDB 资料。不上传完整视频或网盘凭据。模型不可用时保留现有资料。',
                key: ValueKey<String>('tmdb-vision-privacy-notice'),
              ),
              const SizedBox(height: 8),
              KSettingsTile<void>.navigation(
                key: const ValueKey<String>('tmdb-vision-test-connection'),
                leading: const Icon(Icons.image_search_outlined),
                title: const Text('测试 AI 识别连接'),
                description: const Text('使用固定片名验证正式请求与结果解析，不发送私人媒体资料'),
                enabled: !_testingVision,
                value: _testingVision
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onPressed: (_) => _testVisionConnection(),
              ),
              ValueListenableBuilder<String>(
                valueListenable: TmdbVisionModelClient.activity,
                builder: (_, status, __) => Text(status),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: TvSettingsFocusSurface(
              onPressed: _save,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _apiKeySourceLabel => switch (_apiKeyProvider.source) {
        TmdbApiKeySource.user => '当前使用用户 Key',
        TmdbApiKeySource.builtin => '当前使用内置默认 Key',
        TmdbApiKeySource.none => '当前未配置可用 Key',
      };
}
