import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/presentation/library_media_grid.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_poster_wall.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('恢复动作取决于真实错误类型，不读取错误文案', () {
    final controller = CloudResourcesController(
      repository: CloudSourceRepository(storage: MemoryCloudSourceStorage()),
      credentialStore: MemoryCloudCredentialStore(),
    );
    addTearDown(controller.dispose);
    controller.errorMessage = '任何翻译均不影响恢复动作';
    controller.scanFailureTypes = {};
    expect(controller.scanRecoveryType, isNull);
    expect(controller.scanRecoveryLabel, isNull);
    controller.scanFailureTypes = {
      CloudDriveErrorType.network,
      CloudDriveErrorType.notFound,
      CloudDriveErrorType.authentication
    };
    expect(controller.scanRecoveryType, CloudDriveErrorType.authentication);
    expect(controller.scanRecoveryLabel, '重新授权');
    controller.scanFailureTypes = {
      CloudDriveErrorType.notFound,
      CloudDriveErrorType.network
    };
    expect(controller.scanRecoveryType, CloudDriveErrorType.notFound);
    expect(controller.scanRecoveryLabel, '编辑来源');
    controller.scanFailureTypes = {CloudDriveErrorType.authentication};
    expect(controller.scanRecoveryLabel, '重新授权');
    controller.scanFailureTypes = {CloudDriveErrorType.notFound};
    expect(controller.scanRecoveryLabel, '编辑来源');
    controller.scanFailureTypes = {CloudDriveErrorType.network};
    expect(controller.scanRecoveryLabel, isNull);
    expect(MediaRecognitionSettings.describeThreshold(0), contains('空文件仍会忽略'));
    expect(MediaRecognitionSettings.describeThreshold(10), contains('10 字节'));
  });

  testWidgets('640宽2倍文字本地空态真实阈值和设置入口可见可操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;
    await tester.pumpWidget(_host(LibraryMediaGrid(
      capabilities: AppPlatformCapabilities.windows,
      data: LibraryMediaGridViewData(
          currentPath: 'D:/Media',
          filteredBySizeCount: 3,
          recognitionDescription:
              MediaRecognitionSettings.describeThreshold(10 * 1024 * 1024)),
      onRecognitionSettings: () => opened = true,
    )));
    expect(find.text('视频已按大小过滤'), findsOneWidget);
    expect(find.textContaining('大于 10 MB'), findsOneWidget);
    await tester.ensureVisible(find.text('调整识别设置'));
    await tester.tap(find.text('调整识别设置'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('640宽2倍文字本地读取失败显示恢复动作而非无媒体', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var picked = false;
    await tester.pumpWidget(_host(LibraryMediaGrid(
      capabilities: AppPlatformCapabilities.windows,
      data: LibraryMediaGridViewData(
          currentPath: 'D:/Media',
          sourceAccessible: false,
          errorMessage: '目录暂不可用，已保留原有资料；请连接磁盘或重新选择目录'),
      onPickDirectory: () => picked = true,
    )));
    expect(find.text('没有发现视频文件'), findsNothing);
    await tester.ensureVisible(find.text('重新选择目录'));
    await tester.tap(find.text('重新选择目录'));
    expect(picked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('网盘筛选无结果不误报来源没有视频', (tester) async {
    await tester.pumpWidget(_host(CloudResourcePosterWall(
      capabilities: AppPlatformCapabilities.windows,
      sourceId: 'cloud',
      collection: CloudResourceCollection(groups: const []),
      scrapingKeys: const {},
      hasActiveFilters: true,
      onOpenGroup: (_) {},
      onEditTitle: (_) {},
      onScrape: (_) {},
      onRematch: (_) {},
    )));
    expect(find.text('当前筛选下没有匹配视频'), findsOneWidget);
    expect(find.text('没有发现视频文件'), findsNothing);
  });

  testWidgets('640宽2倍文字网盘零阈值空态与设置入口可操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;
    await tester.pumpWidget(_host(CloudResourcePosterWall(
      capabilities: AppPlatformCapabilities.windows,
      sourceId: 'cloud',
      collection: CloudResourceCollection(groups: const []),
      scrapingKeys: const {},
      recognitionDescription: MediaRecognitionSettings.describeThreshold(0),
      onRecognitionSettings: () => opened = true,
      onOpenGroup: (_) {},
      onEditTitle: (_) {},
      onScrape: (_) {},
      onRematch: (_) {},
    )));
    expect(find.textContaining('空文件仍会忽略'), findsOneWidget);
    await tester.ensureVisible(find.text('调整识别设置'));
    await tester.tap(find.text('调整识别设置'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(body: child),
    ));
