import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/version_history.dart';

void main() {
  test('更新弹窗只返回当前运行版本的文案', () {
    final entries = versionHistoryForCurrent('1.4.10');

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.4.10');
  });

  test('版本历史不存在当前版本时不显示错误的旧版本', () {
    expect(versionHistoryForCurrent('9.9.9'), isEmpty);
  });
}
