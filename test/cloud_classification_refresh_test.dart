import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  testWidgets('停留网盘页重刮换作品键后保留人工清空与收藏', (tester) async {
    final repository = MediaLibraryUserStateRepository(
      storage: MemoryMediaLibraryUserStateStorage(),
    );
    final controller = _SnapshotController();
    final oldSeries = _series('source|work|show');
    controller.replaceSnapshot(oldSeries);
    await repository.save(oldSeries.key, MediaLibraryUserState(
      favorite: true,
      categoryOverride: const [],
      genreOverride: const ['自选题材'],
      mediaIds: oldSeries.episodes.map((episode) => episode.stableId).toList(),
    ));
    await tester.pumpWidget(MaterialApp(home: CloudResourcesPage(
      controller: controller,
      userStateRepository: repository,
      settings: TypedSettings(_SettingsBox()),
    )));
    await tester.pumpAndSettle();
    final currentSeries = _series('source|tmdb|tv|42');
    controller.replaceSnapshot(currentSeries);
    await tester.pumpAndSettle();

    final state = controller.classificationStates[currentSeries.key];
    expect(state?.categoryOverride, isEmpty);
    expect(state?.genreOverride, ['自选题材']);
    expect(state?.favorite, isTrue);
    expect(await repository.get(oldSeries.key), isNull);
    expect((await repository.get(currentSeries.key))?.categoryOverride, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _SettingsBox extends Fake implements Box<Object?> {
  @override
  Object? get(Object? key, {Object? defaultValue}) => defaultValue;
}

class _SnapshotController extends CloudResourcesController {
  _SnapshotController() : super(
    repository: CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    ),
    credentialStore: MemoryCloudCredentialStore(),
  );

  final _snapshotChanges = ChangeNotifier();
  CloudMediaLibrary _snapshot = const CloudMediaLibrary(series: [], filters: []);

  @override
  CloudMediaLibrary get mediaLibrarySnapshot => _snapshot;

  @override
  Listenable get mediaLibrarySnapshotListenable => _snapshotChanges;

  @override
  Future<void> load({bool startScan = true}) async {}

  void replaceSnapshot(MediaLibrarySeries series) {
    _snapshot = CloudMediaLibrary(series: [series], filters: const []);
    _snapshotChanges.notifyListeners();
  }

  @override
  void dispose() {
    _snapshotChanges.dispose();
    super.dispose();
  }
}

MediaLibrarySeries _series(String key) => MediaLibrarySeries(
  key: key,
  seriesKey: key,
  title: '同一作品',
  sourceKind: MediaSourceKind.cloud,
  sourceId: 'source',
  sourceName: '网盘',
  isAvailable: true,
  episodes: [MediaLibraryEpisode.cloud(
    stableId: 'episode',
    name: 'S01E01.mkv',
    sourceId: 'source',
    sourceName: '网盘',
    isAvailable: true,
    remoteId: 'episode',
    remotePath: '/作品/S01E01.mkv',
  )],
);
