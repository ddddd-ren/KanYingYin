import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';

class CloudSourcesSettingsPage extends StatefulWidget {
  const CloudSourcesSettingsPage({
    super.key,
    this.controller,
    this.onSourceDeleted,
    this.onSourceScanned,
    this.capabilities,
  });

  final CloudLibraryController? controller;
  final Future<void> Function()? onSourceDeleted;
  final Future<void> Function(String sourceId)? onSourceScanned;
  final AppPlatformCapabilities? capabilities;

  @override
  State<CloudSourcesSettingsPage> createState() =>
      _CloudSourcesSettingsPageState();
}

class _CloudSourcesSettingsPageState extends State<CloudSourcesSettingsPage> {
  late final CloudLibraryController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CloudLibraryController();
    _controller.addListener(_refresh);
    _controller.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _delete(String sourceId) async {
    try {
      await _controller.delete(sourceId);
      try {
        await widget.onSourceDeleted?.call();
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据源已删除，但媒体库刷新失败')),
        );
        return;
      }
      final message = _controller.errorMessage;
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.errorMessage ?? '删除失败')),
      );
    }
  }

  Future<void> _scan(String sourceId) async {
    try {
      final result = await _controller.scanSource(sourceId);
      if (result.cancelled || !mounted) return;
      await widget.onSourceScanned?.call(sourceId);
      if (!mounted) return;
      final message =
          result.failures == 0 ? '网盘媒体扫描完成' : '扫描完成，${result.failures} 个目录读取失败';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.errorMessage ?? '网盘媒体扫描失败')),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = widget.capabilities ?? detectAppPlatform();
    return KSettingsScaffold(
      title: '网盘数据源',
      description: '管理个人夸克、百度、迅雷与 OpenList 网盘媒体来源；OpenList 功能仍在调试。',
      body: _controller.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                KSettingsTile<void>.navigation(
                  key: const ValueKey<String>('configuration-transfer-entry'),
                  leading: const Icon(Icons.import_export_rounded),
                  title: const Text('配置迁移'),
                  description: const Text('用密码加密导出或导入 TMDB 与网盘账号配置'),
                  onPressed: (_) => Modular.to.pushNamed(
                    '/settings/cloud-sources/configuration-transfer',
                  ),
                ),
                if (capabilities.isAndroidTv) ...[
                  KSettingsTile<void>.navigation(
                    key: const ValueKey<String>('tv-pairing-entry'),
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('手机扫码配置'),
                    description: const Text('使用同一局域网中的手机填写 TV 配置'),
                    onPressed: (_) => Modular.to.pushNamed(
                      '/settings/cloud-sources/tv-pairing',
                    ),
                  ),
                  const Divider(height: 24),
                ],
                if (_controller.sources.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('还没有添加网盘数据源')),
                  ),
                if (capabilities.isAndroidTv)
                  for (final source in _controller.sources)
                    _buildTvSourceSection(source),
                if (!capabilities.isAndroidTv)
                  for (final source in _controller.sources)
                    ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(source.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_safeDisplayUrl(source.baseUrl)),
                          Text(_scanSummary(source)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_controller.isQuarkSourceUsable(source.id))
                            IconButton(
                              tooltip: '导入夸克分享',
                              icon: const Icon(
                                  Icons.drive_folder_upload_outlined),
                              onPressed: () => Modular.to.pushNamed(
                                '/settings/cloud-sources/quark/import',
                                arguments: source,
                              ),
                            ),
                          IconButton(
                            tooltip: '扫描数据源',
                            icon: _controller.isScanningSource(source.id)
                                ? const Icon(Icons.stop_circle_outlined)
                                : const Icon(Icons.manage_search_outlined),
                            onPressed: _controller.deleting
                                ? null
                                : _controller.isScanningSource(source.id)
                                    ? () => _controller.cancelScan(source.id)
                                    : _controller.scanningSourceId != null
                                        ? null
                                        : () => _scan(source.id),
                          ),
                          IconButton(
                            tooltip: '删除数据源',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _controller.deleting
                                ? null
                                : () => _delete(source.id),
                          ),
                        ],
                      ),
                      onTap: () => Modular.to.pushNamed(
                        _editorRoute(source.type),
                        arguments: source,
                      ),
                    ),
                const SizedBox(height: 16),
                if (capabilities.isAndroidTv)
                  KSettingsTile<void>.navigation(
                    key: const ValueKey<String>('tv-add-cloud-source'),
                    leading: const Icon(Icons.add_circle_outline_rounded),
                    title: const Text('添加网盘来源'),
                    description: const Text('选择 OpenList、夸克、百度或迅雷'),
                    onPressed: (_) => Modular.to.pushNamed(
                      '/settings/cloud-sources/add',
                    ),
                  ),
                if (!capabilities.isAndroidTv)
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<CloudSourceType>(
                      onSelected: (type) => Modular.to.pushNamed(
                        _editorRoute(type),
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: CloudSourceType.openList,
                          child: Text('添加 OpenList（调试中）'),
                        ),
                        PopupMenuItem(
                          value: CloudSourceType.quark,
                          child: Text('添加夸克网盘'),
                        ),
                        PopupMenuItem(
                          value: CloudSourceType.baidu,
                          child: Text('添加百度网盘'),
                        ),
                        PopupMenuItem(
                          value: CloudSourceType.xunlei,
                          child: Text('添加迅雷网盘'),
                        ),
                      ],
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text('添加网盘来源'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildTvSourceSection(CloudSource source) {
    final scanning = _controller.isScanningSource(source.id);
    final canScan = !_controller.deleting &&
        (scanning || _controller.scanningSourceId == null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: KSettingsSection(
        title: Text(source.name),
        description: Text(
          '${_safeDisplayUrl(source.baseUrl)}\n${_scanSummary(source)}',
        ),
        tiles: <Widget>[
          KSettingsTile<void>.navigation(
            key: ValueKey<String>('tv-cloud-source-edit-${source.id}'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑来源'),
            description: const Text('修改账号、服务地址和媒体目录'),
            onPressed: (_) => Modular.to.pushNamed(
              _editorRoute(source.type),
              arguments: source,
            ),
          ),
          if (_controller.isQuarkSourceUsable(source.id))
            KSettingsTile<void>.navigation(
              key: ValueKey<String>('tv-cloud-source-import-${source.id}'),
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: const Text('导入夸克分享'),
              onPressed: (_) => Modular.to.pushNamed(
                '/settings/cloud-sources/quark/import',
                arguments: source,
              ),
            ),
          KSettingsTile<void>.navigation(
            key: ValueKey<String>('tv-cloud-source-scan-${source.id}'),
            leading: Icon(
              scanning
                  ? Icons.stop_circle_outlined
                  : Icons.manage_search_outlined,
            ),
            title: Text(scanning ? '停止扫描' : '扫描数据源'),
            description: const Text('重新读取已选择目录中的视频和字幕'),
            enabled: canScan,
            onPressed: (_) =>
                scanning ? _controller.cancelScan(source.id) : _scan(source.id),
          ),
          KSettingsTile<void>.navigation(
            key: ValueKey<String>('tv-cloud-source-delete-${source.id}'),
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除数据源'),
            description: const Text('只删除来源、索引和缓存，不删除网盘原始文件'),
            enabled: !_controller.deleting,
            onPressed: (_) => _delete(source.id),
          ),
        ],
      ),
    );
  }

  static String _safeDisplayUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) return '地址格式无效';
    return uri.userInfo.isEmpty ? value : uri.replace(userInfo: '').toString();
  }

  static String _scanSummary(CloudSource source) {
    return switch (source.scanStatus) {
      CloudScanStatus.never => '尚未扫描',
      CloudScanStatus.scanning => '正在扫描 ${source.rootPaths.length} 个目录',
      CloudScanStatus.failed => '扫描失败 · ${source.lastScanFailureCount} 个目录失败',
      CloudScanStatus.completed =>
        '${source.indexedVideoCount} 个视频 · ${source.matchedSubtitleCount} 个字幕'
            '${source.lastScanFailureCount == 0 ? '' : ' · ${source.lastScanFailureCount} 个目录失败'}',
    };
  }

  static String _editorRoute(CloudSourceType type) => switch (type) {
        CloudSourceType.openList => '/settings/cloud-sources/openlist/edit',
        CloudSourceType.quark => '/settings/cloud-sources/quark/edit',
        CloudSourceType.baidu => '/settings/cloud-sources/baidu/edit',
        CloudSourceType.xunlei => '/settings/cloud-sources/xunlei/edit',
      };
}

class CloudSourceTypePickerPage extends StatelessWidget {
  const CloudSourceTypePickerPage({super.key});

  @override
  Widget build(BuildContext context) => KSettingsScaffold(
        title: '添加网盘来源',
        description: '选择要连接的个人网盘类型。',
        body: KSettingsList(
          sections: <Widget>[
            KSettingsSection(
              tiles: <Widget>[
                KSettingsTile<void>.navigation(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('添加 OpenList（调试中）'),
                  onPressed: (_) => Modular.to
                      .pushNamed('/settings/cloud-sources/openlist/edit'),
                ),
                KSettingsTile<void>.navigation(
                  leading: const Icon(Icons.cloud_queue_outlined),
                  title: const Text('添加夸克网盘'),
                  onPressed: (_) => Modular.to
                      .pushNamed('/settings/cloud-sources/quark/edit'),
                ),
                KSettingsTile<void>.navigation(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('添加百度网盘'),
                  onPressed: (_) => Modular.to
                      .pushNamed('/settings/cloud-sources/baidu/edit'),
                ),
                KSettingsTile<void>.navigation(
                  leading: const Icon(Icons.bolt_outlined),
                  title: const Text('添加迅雷网盘'),
                  onPressed: (_) => Modular.to
                      .pushNamed('/settings/cloud-sources/xunlei/edit'),
                ),
              ],
            ),
          ],
        ),
      );
}
