import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/init_page.dart';

void main() {
  test('启动序列在默认路由前执行个人预置导入', () async {
    final events = <String>[];

    await runInitStartupSequence(
      prepareShaders: () async => events.add('shaders'),
      runPreloadedImport: () async => events.add('preload'),
      checkShortcut: () async => events.add('shortcut'),
      navigateToDefaultPage: () => events.add('navigate'),
    );

    expect(events, <String>['shaders', 'preload', 'shortcut', 'navigate']);
  });
}
