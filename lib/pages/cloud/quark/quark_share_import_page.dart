import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_directory_picker.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/providers/quark_import_controller.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';
import 'package:kanyingyin/services/cloud/quark/quark_transfer_target_policy.dart';

typedef QuarkShareTransferFactory = QuarkShareTransfer Function(String cookie);
typedef QuarkImportControllerFactory = QuarkImportController Function(
  QuarkShareTransfer transferService,
);

class QuarkShareImportPage extends StatefulWidget {
  const QuarkShareImportPage({
    super.key,
    required this.source,
    this.cloudLibraryController,
    this.credentialStore,
    this.transferService,
    this.importController,
    this.transferServiceFactory,
    this.importControllerFactory,
  });

  final CloudSource source;
  final CloudLibraryController? cloudLibraryController;
  final CloudCredentialStore? credentialStore;
  final QuarkShareTransfer? transferService;
  final QuarkImportController? importController;
  final QuarkShareTransferFactory? transferServiceFactory;
  final QuarkImportControllerFactory? importControllerFactory;

  @override
  State<QuarkShareImportPage> createState() => _QuarkShareImportPageState();
}

class _QuarkShareImportPageState extends State<QuarkShareImportPage> {
  final _linkController = TextEditingController();
  final _passcodeController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  QuarkShareTransfer? _transferService;
  QuarkImportController? _importController;
  CloudLibraryController? _cloudLibraryController;
  late CloudSource _source;
  QuarkShareInspection? _inspection;
  bool _initializing = true;
  bool _inspecting = false;
  bool _savingTarget = false;
  bool _pageDisposed = false;
  bool _resourcesReleased = false;
  Completer<void>? _activeImport;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cloudController = widget.cloudLibraryController ??
          Modular.get<CloudLibraryController>();
      _cloudLibraryController = cloudController;
      await cloudController.load();
      if (!mounted) return;
      for (final source in cloudController.sources) {
        if (source.id == widget.source.id) {
          _source = source;
          break;
        }
      }
      if (widget.transferService != null && widget.importController != null) {
        _transferService = widget.transferService;
        _importController = widget.importController;
        _importController!.addListener(_refresh);
        if (mounted) setState(() => _initializing = false);
        return;
      }
      final store =
          widget.credentialStore ?? Modular.get<CloudCredentialStore>();
      final credential = await store.read(widget.source.id);
      if (!mounted) return;
      final cookie = credential?.cookie?.trim();
      if (cookie == null || cookie.isEmpty) {
        throw StateError('夸克 Cookie 不存在，请先编辑来源');
      }
      final transfer = widget.transferService ??
          widget.transferServiceFactory?.call(cookie) ??
          QuarkShareTransferService(
            api: QuarkApiClient(cookie: cookie),
          );
      final importer = widget.importController ??
          widget.importControllerFactory?.call(transfer) ??
          QuarkImportController(
            historyRepository: QuarkImportHistoryRepository(),
            transferService: transfer,
            refreshSource:
                Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
          );
      importer.addListener(_refresh);
      if (!mounted) {
        importer.removeListener(_refresh);
        if (widget.importController == null) importer.dispose();
        if (widget.transferService == null) await transfer.close();
        return;
      }
      setState(() {
        _transferService = transfer;
        _importController = importer;
        _initializing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _initializing = false;
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _chooseTransferDirectory() async {
    final controller = _cloudLibraryController;
    if (controller == null) return;
    final selected = await Navigator.of(context).push<List<CloudRemoteRef>>(
      MaterialPageRoute(
        builder: (_) => QuarkDirectoryPickerPage(
          source: _source,
          controller: controller,
          initialSelection: <CloudRemoteRef>[
            if (_source.defaultTransferDirectory != null)
              _source.defaultTransferDirectory!,
          ],
          singleSelection: true,
          title: '选择默认转存目录',
        ),
      ),
    );
    if (!mounted || selected?.isNotEmpty != true) return;
    await _saveTransferTarget(selected!.single);
  }

  Future<bool> _saveTransferTarget(CloudRemoteRef target) async {
    final controller = _cloudLibraryController;
    if (controller == null) {
      if (mounted) setState(() => _errorMessage = '网盘来源尚未加载，请重试');
      return false;
    }
    setState(() {
      _savingTarget = true;
      _errorMessage = null;
    });
    try {
      await controller.load();
      if (!mounted) return false;
      if (controller.errorMessage != null) {
        throw const CloudSourcesLoadException();
      }
      final latest = controller.sources
          .where((source) => source.id == _source.id)
          .firstOrNull;
      if (latest == null) throw StateError('网盘来源不存在');
      final updated = QuarkTransferTargetPolicy.apply(latest, target);
      if (updated == latest) {
        setState(() => _source = latest);
        return true;
      }
      await controller.save(updated);
      if (mounted) {
        final saved = controller.sources
            .where((source) => source.id == updated.id)
            .firstOrNull;
        setState(() => _source = saved ?? updated);
      }
      return true;
    } on Object {
      if (mounted) setState(() => _errorMessage = '转存目录保存失败，请重试');
      return false;
    } finally {
      if (mounted) setState(() => _savingTarget = false);
    }
  }

  Future<void> _inspect() async {
    final service = _transferService;
    if (service == null) return;
    setState(() {
      _inspecting = true;
      _errorMessage = null;
      _inspection = null;
      _selectedIds.clear();
    });
    try {
      final inspection = await service.inspectShare(
        _linkController.text,
        passcode: _passcodeController.text,
      );
      if (!mounted) return;
      setState(() => _inspection = inspection);
    } on Object catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  Future<void> _importSelected() async {
    if (_activeImport != null) return _activeImport!.future;
    final completion = Completer<void>();
    _activeImport = completion;
    try {
      await _performImportSelected();
    } finally {
      if (!completion.isCompleted) completion.complete();
      if (identical(_activeImport, completion)) _activeImport = null;
      if (_pageDisposed) _releaseOwnedResources();
    }
  }

  Future<void> _performImportSelected() async {
    final inspection = _inspection;
    final importer = _importController;
    final target = _source.defaultTransferDirectory;
    if (inspection == null || importer == null || target == null) return;
    final selected = inspection.entries
        .where((entry) => _selectedIds.contains(entry.id))
        .toList();
    if (selected.isEmpty) return;
    if (!await _saveTransferTarget(target)) return;
    try {
      final result = await importer.importEntries(
        sourceId: _source.id,
        shareId: inspection.shareId,
        entries: selected,
        targetDirectoryId: target.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.libraryRefreshed ? '转存完成，已扫描到媒体库' : '文件已转存，但媒体库刷新失败，请重试扫描',
          ),
        ),
      );
    } on QuarkDuplicateImportException {
      if (mounted) setState(() => _errorMessage = '相同内容已在转存或已经转存成功');
    } on Object catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    }
  }

  @override
  void dispose() {
    _pageDisposed = true;
    _importController?.removeListener(_refresh);
    if (_activeImport == null) _releaseOwnedResources();
    _linkController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  void _releaseOwnedResources() {
    if (_resourcesReleased) return;
    _resourcesReleased = true;
    if (widget.importController == null) _importController?.dispose();
    if (widget.transferService == null) {
      final transfer = _transferService;
      if (transfer != null) unawaited(transfer.close());
    }
  }

  @override
  Widget build(BuildContext context) {
    final inspection = _inspection;
    final busy = _importController?.busy == true ||
        _savingTarget ||
        _cloudLibraryController?.scanningSourceId != null;
    final target = _source.defaultTransferDirectory;
    return KSettingsScaffold(
      title: '导入夸克分享',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(child: Text('转存到：${target?.path ?? '未设置'}')),
              OutlinedButton.icon(
                onPressed:
                    _initializing || busy ? null : _chooseTransferDirectory,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(target == null ? '选择目录' : '更改目录'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _linkController,
            decoration: const InputDecoration(
              labelText: '夸克分享链接',
              hintText: 'https://pan.quark.cn/s/...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passcodeController,
            decoration: const InputDecoration(labelText: '提取码（可选）'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _initializing || _inspecting || busy ? null : _inspect,
              icon: const Icon(Icons.search),
              label: Text(_inspecting ? '正在读取' : '查看分享内容'),
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (inspection != null) ...[
            const Divider(height: 32),
            for (final entry in inspection.entries)
              CheckboxListTile(
                value: _selectedIds.contains(entry.id),
                title: Text(entry.name),
                secondary: Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.movie_outlined,
                ),
                onChanged: busy
                    ? null
                    : (selected) => setState(() {
                          if (selected == true) {
                            _selectedIds.add(entry.id);
                          } else {
                            _selectedIds.remove(entry.id);
                          }
                        }),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || _selectedIds.isEmpty || target == null
                  ? null
                  : _importSelected,
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: Text(busy ? '正在转存' : '转存所选内容'),
            ),
          ],
        ],
      ),
    );
  }
}
