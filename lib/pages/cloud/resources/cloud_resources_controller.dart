import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:path/path.dart' as p;

class CloudResourcesController extends ChangeNotifier {
  CloudResourcesController({
    required CloudSourceRepository repository,
    required CloudCredentialStore credentialStore,
    CloudProviderRegistry? providerRegistry,
  })  : _repository = repository,
        _credentialStore = credentialStore,
        _providerRegistry = providerRegistry ?? CloudProviderRegistry();

  final CloudSourceRepository _repository;
  final CloudCredentialStore _credentialStore;
  final CloudProviderRegistry _providerRegistry;
  final List<CloudRemoteRef?> _history = <CloudRemoteRef?>[];

  List<CloudSource> sources = <CloudSource>[];
  List<CloudFileEntry> entries = <CloudFileEntry>[];
  CloudSource? selectedSource;
  CloudRemoteRef? currentDirectory;
  bool isVirtualRoot = false;
  bool loading = false;
  String query = '';
  String? errorMessage;

  int _generation = 0;
  bool _disposed = false;

  bool get canGoBack => _history.isNotEmpty;

  List<CloudFileEntry> get visibleEntries {
    final keyword = query.trim().toLowerCase();
    final filtered = entries
        .where(
          (entry) =>
              (entry.isDirectory ||
                  LocalVideoFileTypes.isVideoPath(entry.name)) &&
              (keyword.isEmpty || entry.name.toLowerCase().contains(keyword)),
        )
        .toList(growable: false);
    filtered.sort((first, second) {
      if (first.isDirectory != second.isDirectory) {
        return first.isDirectory ? -1 : 1;
      }
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    return filtered;
  }

  Future<void> load() async {
    final generation = ++_generation;
    loading = true;
    errorMessage = null;
    _notify();
    try {
      final loadedSources = (await _repository.getAll())
          .where((source) => source.enabled)
          .toList(growable: false);
      if (!_isCurrent(generation)) return;
      sources = loadedSources;
      final currentId = selectedSource?.id;
      final nextId = loadedSources.any((source) => source.id == currentId)
          ? currentId
          : loadedSources.firstOrNull?.id;
      loading = false;
      await selectSource(nextId);
    } on Object {
      if (!_isCurrent(generation)) return;
      sources = <CloudSource>[];
      selectedSource = null;
      currentDirectory = null;
      entries = <CloudFileEntry>[];
      loading = false;
      errorMessage = '网盘来源加载失败';
      _notify();
    }
  }

  Future<void> selectSource(String? sourceId) async {
    final generation = ++_generation;
    _history.clear();
    query = '';
    entries = <CloudFileEntry>[];
    currentDirectory = null;
    isVirtualRoot = false;
    errorMessage = null;
    selectedSource = sourceId == null
        ? null
        : sources.where((source) => source.id == sourceId).firstOrNull;
    final source = selectedSource;
    if (source == null) {
      loading = false;
      _notify();
      return;
    }
    final roots = source.remoteRoots;
    if (roots.length > 1) {
      _showVirtualRoot(source);
      return;
    }
    if (roots.isEmpty) {
      loading = false;
      errorMessage = '该来源还没有配置媒体根目录';
      _notify();
      return;
    }
    await _loadDirectory(
      roots.single,
      generation: generation,
      pushHistory: false,
    );
  }

  Future<void> _loadDirectory(
    CloudRemoteRef directory, {
    required int generation,
    required bool pushHistory,
    CloudRemoteRef? previousDirectory,
    bool previousWasVirtualRoot = false,
  }) async {
    final source = selectedSource;
    if (source == null) return;
    loading = true;
    errorMessage = null;
    _notify();
    CloudDriveClient? client;
    try {
      client = _providerRegistry.createClient(source, _credentialStore);
      final loadedEntries = await client.listDirectory(directory);
      if (!_isCurrent(generation)) return;
      if (pushHistory) {
        _history.add(previousWasVirtualRoot ? null : previousDirectory);
      }
      currentDirectory = directory;
      entries = loadedEntries;
      isVirtualRoot = false;
    } on CloudDriveException catch (error) {
      if (!_isCurrent(generation)) return;
      errorMessage = _providerRegistry.errorMessage(source.type, error);
    } on Object {
      if (!_isCurrent(generation)) return;
      errorMessage = '网盘目录加载失败';
    } finally {
      await client?.close();
      if (_isCurrent(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> openDirectory(CloudRemoteRef directory) {
    final generation = ++_generation;
    return _loadDirectory(
      directory,
      generation: generation,
      pushHistory: true,
      previousDirectory: currentDirectory,
      previousWasVirtualRoot: isVirtualRoot,
    );
  }

  Future<void> goBack() async {
    if (_history.isEmpty || loading) return;
    final previous = _history.removeLast();
    if (previous == null) {
      final source = selectedSource;
      if (source != null) _showVirtualRoot(source);
      return;
    }
    final generation = ++_generation;
    await _loadDirectory(
      previous,
      generation: generation,
      pushHistory: false,
    );
  }

  Future<void> refresh() async {
    if (loading) return;
    final source = selectedSource;
    if (source == null) return;
    if (isVirtualRoot) {
      _showVirtualRoot(source);
      return;
    }
    final directory = currentDirectory;
    if (directory == null) return;
    final generation = ++_generation;
    await _loadDirectory(
      directory,
      generation: generation,
      pushHistory: false,
    );
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _notify();
  }

  void _showVirtualRoot(CloudSource source) {
    entries = source.remoteRoots
        .map(
          (root) => CloudFileEntry(
            id: root.id,
            remotePath: root.path,
            name: p.posix.basename(root.path),
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        )
        .toList(growable: false);
    currentDirectory = null;
    isVirtualRoot = true;
    loading = false;
    errorMessage = null;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
