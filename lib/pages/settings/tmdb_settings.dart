import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/utils/storage.dart';

class TmdbSettingsPage extends StatefulWidget {
  const TmdbSettingsPage({super.key});

  @override
  State<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends State<TmdbSettingsPage> {
  static const _apiKeySetting = 'tmdbApiKey';
  static const _autoScrapeSetting = 'tmdbAutoScrape';
  late final TextEditingController _apiKeyController;
  bool _autoScrape = true;
  bool _obscureApiKey = true;
  bool _testing = false;
  late TmdbScrapeOptions _options;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(
      text: GStorage.setting.getTyped<String>(
        _apiKeySetting,
        defaultValue: '',
      ),
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
    await GStorage.setting.put(_apiKeySetting, _apiKeyController.text.trim());
    await GStorage.setting.put(_autoScrapeSetting, _autoScrape);
    await GStorage.setting.put('tmdbScrapeOptions', _options.toMap());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('TMDB 设置已保存')),
    );
  }

  Future<void> _testConnection() async {
    final key = _apiKeyController.text.trim();
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
    return Scaffold(
      appBar: const SysAppBar(title: Text('TMDB 刮削设置')),
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
}
