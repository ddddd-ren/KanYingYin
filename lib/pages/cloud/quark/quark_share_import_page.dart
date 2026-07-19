import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/providers/quark_import_controller.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';

class QuarkShareImportPage extends StatefulWidget {
  const QuarkShareImportPage({
    super.key,
    required this.source,
    this.credentialStore,
    this.transferService,
    this.importController,
  });

  final CloudSource source;
  final CloudCredentialStore? credentialStore;
  final QuarkShareTransfer? transferService;
  final QuarkImportController? importController;

  @override
  State<QuarkShareImportPage> createState() => _QuarkShareImportPageState();
}

class _QuarkShareImportPageState extends State<QuarkShareImportPage> {
  final _linkController = TextEditingController();
  final _passcodeController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  QuarkShareTransfer? _transferService;
  QuarkImportController? _importController;
  QuarkShareInspection? _inspection;
  bool _initializing = true;
  bool _inspecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
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
      final cookie = credential?.cookie?.trim();
      if (cookie == null || cookie.isEmpty) {
        throw StateError('夸克 Cookie 不存在，请先编辑来源');
      }
      final transfer = widget.transferService ??
          QuarkShareTransferService(
            api: QuarkApiClient(cookie: cookie),
          );
      final importer = widget.importController ??
          QuarkImportController(
            historyRepository: QuarkImportHistoryRepository(),
            transferService: transfer,
            scanSource: (sourceId) async {
              await Modular.get<CloudLibraryController>().scanSource(sourceId);
            },
            refreshLibrary: () async {
              await Modular.get<LocalController>().reloadCloudLibraryIndex();
            },
          );
      importer.addListener(_refresh);
      if (!mounted) {
        await transfer.close();
        importer.dispose();
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
    final inspection = _inspection;
    final importer = _importController;
    final target = widget.source.defaultTransferDirectory;
    if (inspection == null || importer == null || target == null) return;
    final selected = inspection.entries
        .where((entry) => _selectedIds.contains(entry.id))
        .toList();
    if (selected.isEmpty) return;
    try {
      for (final entry in selected) {
        await importer.importEntry(
          sourceId: widget.source.id,
          shareId: inspection.shareId,
          entry: entry,
          targetDirectoryId: target.id,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('转存完成，媒体库已刷新')),
      );
    } on QuarkDuplicateImportException {
      if (mounted) setState(() => _errorMessage = '相同内容已在转存或已经转存成功');
    } on Object catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    }
  }

  @override
  void dispose() {
    _importController?.removeListener(_refresh);
    if (widget.importController == null) _importController?.dispose();
    if (widget.transferService == null) _transferService?.close();
    _linkController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inspection = _inspection;
    final busy = _importController?.busy == true;
    return Scaffold(
      appBar: AppBar(title: const Text('导入夸克分享')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('转存到：${widget.source.defaultTransferDirectory?.path ?? '未设置'}'),
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
              onPressed: _initializing || _inspecting ? null : _inspect,
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
              onPressed: busy ||
                      _selectedIds.isEmpty ||
                      widget.source.defaultTransferDirectory == null
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
