import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/utils/storage.dart';

class TmdbSettingsPage extends StatefulWidget {
  const TmdbSettingsPage({
    super.key,
    required this.credentialManager,
    this.apiKeyProvider,
  });

  final TmdbCredentialManager credentialManager;
  final TmdbApiKeyProvider? apiKeyProvider;

  @override
  State<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends State<TmdbSettingsPage> {
  static const _autoScrapeSetting = 'tmdbAutoScrape';
  late final TextEditingController _apiKeyController;
  bool _autoScrape = true;
  bool _obscureApiKey = true;
  bool _testing = false;
  late final TmdbApiKeyProvider _apiKeyProvider;
  late TmdbScrapeOptions _options;

  @override
  void initState() {
    super.initState();
    _apiKeyProvider = widget.apiKeyProvider ??
        TmdbApiKeyProvider(userKeyReader: widget.credentialManager.read);
    _apiKeyController = TextEditingController(
      text: widget.credentialManager.read(),
    );
    _autoScrape = GStorage.setting.getTyped<bool>(
      _autoScrapeSetting,
      defaultValue: true,
    );
    _options = TmdbScrapeOptions.fromMap(
      GStorage.setting.get('tmdbScrapeOptions'),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.credentialManager.save(_apiKeyController.text);
      await GStorage.setting.put(_autoScrapeSetting, _autoScrape);
      await GStorage.setting.put('tmdbScrapeOptions', _options.toMap());
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB 凭据保存失败，请稍后重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('TMDB 设置已保存')),
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
    await GStorage.setting.delete('tmdbMetadataCache');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('TMDB 元数据缓存已清理')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KSettingsScaffold(
      title: 'TMDB 刮削设置',
      description: '管理海报与影片资料的凭据、语言和覆盖规则。',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: 'TMDB API Key',
              helperText: '密钥仅保存在本机，用于获取海报和影片信息',
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
          const Divider(height: 32),
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
              DropdownMenuItem(value: TmdbMediaTypeMode.tv, child: Text('电视剧')),
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
                setState(
                    () => _options = _options.copyWith(confidenceMode: value));
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.network_check_outlined),
            title: const Text('测试 TMDB 连接'),
            subtitle: const Text('验证当前密钥和网络是否可用'),
            trailing: _testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _testing ? null : _testConnection,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清理元数据缓存'),
            subtitle: const Text('不会删除媒体文件或已经写入媒体库的信息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearMetadataCache,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
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
