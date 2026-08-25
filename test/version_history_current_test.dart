import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/features/version/presentation/version_changelog_dialog.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/utils/version_history.dart';

void main() {
  test('一点零十正式版展示媒体标签、启动和海报修复', () {
    final entries = versionHistoryForCurrent('1.0.10');

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.0.10');
    expect(entries.single.isPrerelease, isFalse);
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      'Windows',
      '码率',
      '字幕轨道',
      '空白窗口',
      'TMDB',
      '海报',
      '不会修改',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 一点零六正式版只展示 Android 功能', () {
    final entries = versionHistoryForCurrent(
      '1.0.10',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.0.6');
    expect(entries.single.isPrerelease, isFalse);
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '手机和平板',
      '码率',
      '检查 GitHub',
      '关于',
      '海报',
      '不会修改',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
    expect(changes, isNot(contains('空白窗口')));
  });

  test('一点零九正式版说明海报和每个选集的媒体技术标签', () {
    final entries = versionHistoryForCurrent('1.0.9');

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.0.9');
    expect(entries.single.isPrerelease, isFalse);
    final changes = entries.single.changes.join('\n');
    for (final text in <String>['4K', '杜比视界', '选集', '不会修改或删除']) {
      expect(changes, contains(text));
    }
  });

  test('二点一六七说明网盘海报状态保持稳定', () {
    final entries = versionHistoryForCurrent('2.1.167');

    expect(entries, hasLength(1));
    expect(entries.single.version, '2.1.167');
    expect(entries.single.isPrerelease, isTrue);
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      'Windows',
      '网盘资源',
      '网盘资源的匹配状态或季度信息更新时',
      '已经显示的海报保持不变',
      '不再再次加载',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    for (final unsupportedClaim in <String>['已经扫描到', '保证匹配']) {
      expect(changes, isNot(contains(unsupportedClaim)));
    }
  });

  test('二点一六零说明播放器网速展示和提示边界', () {
    final entries = versionHistoryForCurrent(
      '2.1.160',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    expect(entries.single.version, '2.1.160');
    expect(entries.single.isPrerelease, isTrue);
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      'Android 手机',
      '进度条',
      '实时网速',
      '当前视频',
      '重新连接',
      '读取失败',
      'APK/AAB 已构建并交付',
      '包级校验通过',
      '未安装到设备',
      '真机播放与 UI 验收尚未完成',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    for (final unsupportedClaim in <String>[
      '网速提升',
      '保证达到',
      'Android TV',
      'tvTest',
    ]) {
      expect(changes, isNot(contains(unsupportedClaim)));
    }
  });

  test('一点零八正式版为 Android mobile 继续显示一点零四更新', () {
    final entries = versionHistoryForCurrent(
      '1.0.8',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.0.4');
    expect(entries.single.isPrerelease, isFalse);
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '动画电影',
      '云盘外挂字幕',
      '重复 UTF-8 BOM',
      '裸集号',
      '视频已隐藏',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    for (final tvOnlyText in <String>[
      'Android TV',
      'tvTest',
      '遥控器',
      '手机扫码配置',
      '海信',
    ]) {
      expect(changes, isNot(contains(tvOnlyText)));
    }
  });

  test('一点零八正式版说明 TMDB 海报网络恢复和本机代理边界', () {
    const posterProxyCopy =
        '改善 TMDB 海报的网络连接。部分网络可以正常获取影片资料，但无法直接下载海报；遇到这种情况时，可保持 Clash Verge 等本机代理在后台运行，并选择能够访问 TMDB 图片的节点。关闭系统代理不影响已经运行的本机代理，但完全退出代理软件后，海报可能再次无法加载。';
    final entries = versionHistoryForCurrent('1.0.8');

    expect(entries, hasLength(1));
    expect(entries.single.isPrerelease, isFalse);
    final changes = entries.single.changes.join('\n');
    expect(changes, contains(posterProxyCopy));
    for (final text in <String>[
      'TMDB 海报',
      '手动匹配',
      'Clash Verge',
      '网盘',
      '不会修改、删除、改名或移动',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五七修复网盘搜索空状态提示错误', () {
    final entries = versionHistoryForCurrent('2.1.157');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '搜索无匹配结果',
      '视频已隐藏',
      '没有找到匹配的视频',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五六修复重复 BOM 字幕加载错误', () {
    final entries = versionHistoryForCurrent('2.1.156');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      'ASS 字幕',
      '重复 UTF-8 BOM',
      '已有错误字幕缓存',
      '自动修复',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五五修复作品目录裸集号识别', () {
    final entries = versionHistoryForCurrent('2.1.155');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '作品子目录',
      'BD 4K 1',
      '同一部剧集',
      '自动刷新',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五四修复云盘字幕文件名显示', () {
    final entries = versionHistoryForCurrent('2.1.154');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '云盘外挂字幕',
      '原始字幕文件名',
      '哈希键',
      'PGS',
      'Android TV',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五二支持动漫电影双入口分类', () {
    final entries = versionHistoryForCurrent('2.1.152');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '动画电影',
      '动漫和电影',
      '动画电视剧',
      '动漫和电视剧',
      'TMDB',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五一修复剧场版 TMDB 匹配与动漫分类', () {
    final entries = versionHistoryForCurrent('2.1.151');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '剧场版序号',
      'TMDB',
      '高度相似',
      '候选领先差',
      '火影忍者',
      '动画题材',
      '动漫',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一五零修复动漫作品重复分类', () {
    final entries = versionHistoryForCurrent('2.1.150');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '动画电影',
      '动画剧集',
      '动漫入口',
      '电影',
      '电视剧',
      '互不重复',
      'TMDB',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一四九修复电影音轨数量误判与 TMDB 类型异常', () {
    final entries = versionHistoryForCurrent('2.1.149');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      '3Audio',
      '集号',
      '电视剧',
      'TMDB',
      '媒体根目录',
      'Main10',
      'SSDSSE',
      '不会修改或删除',
      '不会改名、移动',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一四八区分 TV 返回与 Windows 播放刮削更新', () {
    final entries = versionHistoryForCurrent('2.1.148');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    for (final text in <String>[
      'Android TV',
      '选集',
      '横屏',
      'Windows',
      'TMDB',
      '10bit',
      'HDR 直通',
      'HDR 转 SDR',
      'GLSL',
      '不会修改或删除',
      '海信实机验收未完成',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一四七说明 Android 9 TV 性能和选集焦点优化', () {
    final entries = versionHistoryForCurrent('2.1.147');

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.isPrerelease, isTrue);
    final changes = entry.changes.join('\n');
    for (final text in <String>[
      'Android 9',
      'Android TV/Google TV',
      '缓存快照',
      '夸克',
      '百度',
      '播放稳定性',
      '选集',
      '遥控器焦点',
      '正在播放',
      '个人预置',
      '不会修改或删除',
      '海信实机验收未完成',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一四三说明 TV 文件选择和目录顶部焦点修复', () {
    final entries = versionHistoryForCurrent('2.1.143');

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.isPrerelease, isTrue);
    final changes = entry.changes.join('\n');
    for (final text in <String>[
      'Android TV',
      '系统文件选择器',
      '.kyymeta',
      '.kyyconfig',
      '应用缓存',
      '选择当前目录',
      '确定',
      '遥控器',
      '不会修改或删除',
      '海信实机验收未完成',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一四二说明 TV 配置迁移和焦点反馈', () {
    final entries = versionHistoryForCurrent('2.1.142');

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.isPrerelease, isTrue);
    final changes = entry.changes.join('\n');
    for (final text in <String>[
      'Android TV',
      'Android TV/Google TV',
      'tvTest',
      '焦点',
      '同一局域网',
      '手机扫码配置',
      'OpenList',
      '夸克',
      '百度',
      '迅雷',
      '.kyyconfig',
      '回滚',
      '不会修改或删除',
      '海信实机验收未完成',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('一点零六正式版展示分类、剧集匹配和自选目录更新', () {
    final entries = versionHistoryForCurrent('1.0.6');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isFalse);
    for (final text in <String>[
      'Windows',
      'Android',
      '电影',
      '动漫',
      '电视剧',
      '剧集',
      'TMDB',
      'S01E01',
      '自选目录',
      '迁移',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains(r'D:\看影音')));
  });

  test('Android 一点零三正式版只展示 Android 功能', () {
    final entries = versionHistoryForCurrent(
      '1.0.6',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '1.0.3');
    expect(entry.isPrerelease, isFalse);
    for (final text in <String>[
      'Android',
      '电影',
      '动漫',
      '电视剧',
      'TMDB',
      'S01E01',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
    expect(changes, isNot(contains('EXE')));
  });

  test('二点一三七支持单集刮削和错误隔离', () {
    final entries = versionHistoryForCurrent('2.1.137');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '2.1.137');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows',
      '单集',
      '本地',
      'TMDB',
      '隔离',
      '作品归属',
      '季度',
      '集数',
      '断网',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一三八支持自定义安装目录和 Android TV 测试版', () {
    final entries = versionHistoryForCurrent('2.1.138');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '2.1.138');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows',
      'EXE',
      '安装向导',
      '目录选择页',
      '自选',
      '实际安装目录',
      'Android TV 测试版',
      'Android TV/Google TV',
      'tvTest',
      '遥控器',
      '同一局域网',
      '手机扫码配置',
      'VIDAA',
      '实机验收未完成',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('一点零五正式版综合二点一零一至二点一零三更新', () {
    final entries = versionHistoryForCurrent('1.0.5');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '1.0.5');
    expect(entry.isPrerelease, isFalse);
    for (final text in <String>[
      'Windows',
      'Android',
      '2.1.101',
      '2.1.103',
      '诊断日志',
      '夸克',
      '自适应',
      '系统栏',
      'TrueHD',
      '沉浸',
      '正式版',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 一点零二正式版只展示近期移动端功能更新', () {
    final entries = versionHistoryForCurrent(
      '1.0.5',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '1.0.2');
    expect(entry.isPrerelease, isFalse);
    for (final text in <String>[
      '2.1.101',
      '2.1.103',
      '诊断日志',
      'TrueHD',
      '夸克',
      '自适应',
      '系统栏',
      '沉浸',
      '正式版',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
  });

  test('二点一九十八说明安卓 Anime4K 路径与更新说明入口', () {
    final entries = versionHistoryForCurrent('2.1.98');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows',
      'Android',
      'Anime4K',
      '逐个',
      '更新说明',
      '普通播放',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 二点一九十八只展示本轮移动端更新', () {
    final entries = versionHistoryForCurrent(
      '2.1.98',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '2.1.98');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Android',
      'Anime4K',
      '逐个',
      '更新说明',
      '普通播放',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
  });

  test('二点一九十七说明安卓夸克百度高码率读取优化', () {
    final entries = versionHistoryForCurrent('2.1.97');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows',
      'Android',
      '夸克',
      '百度',
      '六路',
      '40 MiB',
      '128 MiB',
      '迅雷',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 二点一九十七只展示本轮移动端更新', () {
    final entries = versionHistoryForCurrent(
      '2.1.97',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '2.1.97');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Android',
      '夸克',
      '百度',
      '六路',
      '40 MiB',
      '128 MiB',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
    expect(changes, isNot(contains('迅雷')));
  });

  test('二点一九十六说明日志复制与安卓 Anime4K 修复', () {
    final entries = versionHistoryForCurrent('2.1.96');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows',
      'Android',
      '日志',
      '复制',
      'Anime4K',
      '自动',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 二点一九十六只展示本轮移动端更新', () {
    final entries = versionHistoryForCurrent(
      '2.1.96',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '2.1.96');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Android',
      '日志',
      '复制',
      'Anime4K',
      '自动',
      'GPU',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
  });

  test('二点一九十五说明双平台网盘读取优化', () {
    final entries = versionHistoryForCurrent('2.1.95');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows',
      'Android',
      '网盘',
      '预取',
      '缓存',
      '读取速度',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 二点一九十五只展示本轮移动端更新', () {
    final entries = versionHistoryForCurrent(
      '2.1.95',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '2.1.95');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Android',
      '三路',
      '24 MiB',
      '128 MiB',
      '64 MiB',
      '读取速度',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
  });

  test('二点一九十四说明 Windows 测试版风险修复边界', () {
    final entries = versionHistoryForCurrent('2.1.94');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Windows 测试版',
      'Android 未构建',
      '迅雷',
      'Anime4K',
      '播放器',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('一点零三正式版同步 Android 一点零零安装包', () {
    final entries = versionHistoryForCurrent('1.0.3');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isFalse);
    for (final text in <String>[
      '综合近期版本更新',
      'Android 1.0.0',
      '硬件解码',
      '迅雷',
      '媒体库',
      '系统存储访问框架',
      'MediaCodec',
      '画中画',
      '后台播放',
      '刮削资料',
      'TMDB',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('Android 首次正式版弹窗只展示 Android 功能', () {
    final entries = versionHistoryForCurrent(
      '1.0.3',
      platform: AppPlatformKind.android,
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.version, '1.0.0');
    expect(entry.isPrerelease, isFalse);
    for (final text in <String>[
      'Android 首次正式发布',
      '系统存储访问框架',
      'MediaCodec',
      '后台播放',
      '画中画',
      'PGS',
      'TrueHD',
      '个人网盘媒体播放',
      '系统 WebView',
      '不会修改、删除或转码',
    ]) {
      expect(changes, contains(text));
    }
    expect(changes, isNot(contains('Windows')));
    expect(changes, isNot(contains('迅雷')));
  });

  test('二点一九十三支持刮削资料跨设备迁移', () {
    final entries = versionHistoryForCurrent('2.1.93');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '刮削资料',
      '本地',
      '网盘',
      '海报',
      '背景图',
      '不会包含',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一九十补齐迅雷目录设备签名', () {
    final entries = versionHistoryForCurrent('2.1.90');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '迅雷',
      '目录',
      '设备签名',
      '官方',
      'Android',
      '更新暂停',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十九修复迅雷登录后的目录读取', () {
    final entries = versionHistoryForCurrent('2.1.89');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '迅雷',
      '目录',
      'Shield Token',
      '网页',
      '安卓客户端',
      '重试一次',
      'Android',
      '更新暂停',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十八固化 Windows 联合验证播放器组件', () {
    final entries = versionHistoryForCurrent('2.1.88');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      'Windows',
      'D3D11',
      'TrueHD',
      'PGS',
      '联合验证',
      'Android',
      '更新暂停',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十七修复 Windows 四K帧率和 Android PGS 字幕', () {
    final entries = versionHistoryForCurrent('2.1.87');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      'Windows',
      '4K',
      'D3D11',
      '硬件解码',
      'Android',
      'PGS',
      'GPU',
      '真机复验',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十六固定平板横屏并优化解码与网盘链路', () {
    final entries = versionHistoryForCurrent('2.1.86');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '平板',
      '双向横屏',
      '视频解码器',
      '软件解码',
      '4 MiB',
      '复用网络连接',
      '三路并发',
      '真机复验',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十五修复 Android 字幕并兼容 TrueHD 音轨', () {
    final entries = versionHistoryForCurrent('2.1.85');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      'Android',
      '内嵌字幕',
      '外部字幕',
      '配音/音轨',
      'TrueHD',
      '手机和平板',
      '真机验收尚未完成',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十四修复 Android 黑屏、返回和图片连接错误', () {
    final entries = versionHistoryForCurrent('2.1.84');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    for (final text in <String>[
      '有声音无画面',
      '手机和平板',
      '海报墙',
      'TMDB',
      '字幕',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十三交付 Android 测试版安装包', () {
    final entries = versionHistoryForCurrent('2.1.83');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Android',
      '系统存储访问框架',
      'MediaCodec',
      '画中画',
      'WebView2',
      '系统 WebView',
      '签名包',
      '真机验收尚未完成',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十二修复网页令牌目录加载', () {
    final entries = versionHistoryForCurrent('2.1.82');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      'Refresh Token',
      'Shield Token',
      '目录加载失败',
      '授权成功',
      '账号',
      '目录请求',
      '重试一次',
      '当前目录没有子文件夹',
      '不会写入日志',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一八十一支持网页端 Refresh Token', () {
    final entries = versionHistoryForCurrent('2.1.81');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      '应用内',
      '设备验证',
      'pan.xunlei.com',
      'Refresh Token',
      '安卓客户端',
      '客户端不匹配',
      '网页端客户端参数',
      '服务端轮换',
      'Windows 安全凭据',
      'WebView2',
      '阻止下载',
      '自动继续登录',
      '不安全页面',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一七十三说明应用内设备验证和密码错误提示', () {
    final entries = versionHistoryForCurrent('2.1.73');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      '应用内',
      '设备验证',
      '自动继续登录',
      '密码错误',
      'WebView2',
      '临时数据',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一七十二说明迅雷设备验证空白页修复', () {
    final entries = versionHistoryForCurrent('2.1.72');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      '设备验证',
      '空白页',
      '设备签名',
      '系统浏览器',
      '日志',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一七十一说明 TMDB 直连和迅雷 Token 授权', () {
    final entries = versionHistoryForCurrent('2.1.71');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      '官方备用端点',
      'Refresh Token',
      '名称清理',
      '日志',
      '本地扫描与播放',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一七十说明 TMDB 晚启动代理自动恢复', () {
    final entries = versionHistoryForCurrent('2.1.70');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      '代理软件',
      '重新探测',
      '自动重试',
      'API Key',
      '播放器',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('二点一六十九说明迅雷网盘与 OpenList 快捷入口', () {
    final entries = versionHistoryForCurrent('2.1.69');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    for (final text in <String>[
      '迅雷网盘',
      '账号密码不保存',
      '原画播放',
      'OpenList 入口',
      '不会修改或删除',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('一点零点二说明累积正式版更新', () {
    final entries = versionHistoryForCurrent('1.0.2');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isFalse);
    for (final text in [
      '清除',
      '剧场版',
      'OVA',
      'TMDB',
      '连续集号',
      '第 1 季',
      '隐藏',
      '恢复',
      'TrueHD',
      'PGS',
      '硬件解码',
      '零拷贝',
      'Anime4K',
      '本地与网盘',
      '播放器',
      '不会修改',
    ]) {
      expect(changes, contains(text));
    }
  });

  test('一点零一点说明累积正式版更新', () {
    final entries = versionHistoryForCurrent('1.0.1');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isFalse);
    expect(changes, contains('本地与网盘'));
    expect(changes, contains('目录选择'));
    expect(changes, contains('转存目录'));
    expect(changes, contains('铺满'));
    expect(changes, contains('动漫番剧'));
    expect(changes, contains('Anime4K'));
    expect(changes, contains('快捷方式'));
    expect(changes, contains('TMDB'));
    expect(changes, contains('播放器'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一五十五说明海报铺满与圆角抗锯齿', () {
    final entries = versionHistoryForCurrent('2.1.55');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('本地与网盘'));
    expect(changes, contains('铺满'));
    expect(changes, contains('浅色白边'));
    expect(changes, contains('抗锯齿'));
    expect(changes, contains('夸克'));
    expect(changes, contains('百度'));
    expect(changes, contains('OpenList'));
    expect(changes, contains('播放器'));
    expect(changes, contains('TMDB'));
    expect(changes, contains('不会修改或删除'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一五十六说明网盘多选目录一键清除', () {
    final entries = versionHistoryForCurrent('2.1.56');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('清除已选'));
    expect(changes, contains('夸克'));
    expect(changes, contains('百度'));
    expect(changes, contains('OpenList'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一五十七说明来源编辑页清除媒体根目录', () {
    final entries = versionHistoryForCurrent('2.1.57');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('来源编辑页'));
    expect(changes, contains('媒体根目录'));
    expect(changes, contains('一键清除'));
    expect(changes, contains('夸克'));
    expect(changes, contains('百度'));
    expect(changes, contains('OpenList'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一五十八说明剧场版识别和播放器防重', () {
    final entries = versionHistoryForCurrent('2.1.58');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('剧场版'));
    expect(changes, contains('独立电影'));
    expect(changes, contains('多版本'));
    expect(changes, contains('海报缓存'));
    expect(changes, contains('重复点击'));
    expect(changes, contains('播放器'));
    expect(changes, contains('夸克'));
    expect(changes, contains('百度'));
    expect(changes, contains('OpenList'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一五十九说明方括号发布名识别和旧索引重试', () {
    final entries = versionHistoryForCurrent('2.1.59');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('发布组'));
    expect(changes, contains('校验码'));
    expect(changes, contains('错误索引'));
    expect(changes, contains('TMDB 未匹配'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十说明连续编号合并和手动名称优先', () {
    final entries = versionHistoryForCurrent('2.1.60');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('迪迦奥特曼01'));
    expect(changes, contains('连续编号'));
    expect(changes, contains('手动名称'));
    expect(changes, contains('TMDB 标题'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十一说明混合目录资源恢复海报墙显示', () {
    final entries = versionHistoryForCurrent('2.1.61');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('海报墙'));
    expect(changes, contains('导演剪辑版'));
    expect(changes, contains('10th'));
    expect(changes, contains('ASS 字幕'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十二说明单一第一季海报标题精简', () {
    final entries = versionHistoryForCurrent('2.1.62');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('单一第一季'));
    expect(changes, contains('多季作品'));
    expect(changes, contains('非第一季'));
    expect(changes, contains('播放路径'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十三说明退出清理、异步字幕和网盘稳定性修复', () {
    final entries = versionHistoryForCurrent('2.1.63');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('退出'));
    expect(changes, contains('字幕目录'));
    expect(changes, contains('百度网盘'));
    expect(changes, contains('刷新失败'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十四说明网盘海报墙可隐藏和恢复具体视频版本', () {
    final entries = versionHistoryForCurrent('2.1.64');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('隐藏视频'));
    expect(changes, contains('具体版本'));
    expect(changes, contains('恢复'));
    expect(changes, contains('重新扫描'));
    expect(changes, contains('不会修改或删除网盘文件'));
  });

  test('二点一六十五说明 TrueHD 与 PGS 解码修复并保留零拷贝', () {
    final entries = versionHistoryForCurrent('2.1.65');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('TrueHD'));
    expect(changes, contains('PGS'));
    expect(changes, contains('硬件解码'));
    expect(changes, contains('零拷贝'));
    expect(changes, contains('Anime4K'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十六说明 TMDB 名称清理和网盘资源性能优化', () {
    final entries = versionHistoryForCurrent('2.1.66');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('TMDB'));
    expect(changes, contains('视频编码'));
    expect(changes, contains('网盘资源页'));
    expect(changes, contains('手动刮削'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十七说明含发布站网址的网盘目录仍扫描视频', () {
    final entries = versionHistoryForCurrent('2.1.67');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('发布站网址'));
    expect(changes, contains('资源容器'));
    expect(changes, contains('TMDB'));
    expect(changes, contains('广告'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一六十八说明清理流媒体平台和发布组后缀', () {
    final entries = versionHistoryForCurrent('2.1.68');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('DSNP'));
    expect(changes, contains('HBOMax'));
    expect(changes, contains('BlackTV'));
    expect(changes, contains('TMDB 搜索词'));
    expect(changes, contains('不会修改或删除'));
  });

  test('二点一四十九说明 Anime4K 效率档使用官方快速组合', () {
    final entries = versionHistoryForCurrent('2.1.49');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('效率档'));
    expect(changes, contains('官方快速组合'));
    expect(changes, contains('动画画质增强'));
    expect(changes, contains('显卡'));
  });

  test('更新弹窗只返回当前运行版本的文案', () {
    final entries = versionHistoryForCurrent('1.4.10');

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.4.10');
  });

  test('二点零点八说明升级不删除视频文件', () {
    final entries = versionHistoryForCurrent('2.0.8');

    expect(entries, hasLength(1));
    expect(entries.single.changes.join('\n'), contains('不会删除用户的原始视频文件'));
  });

  test('二点零点九显示桌面快捷方式图标修复', () {
    final entries = versionHistoryForCurrent('2.0.9');

    expect(entries, hasLength(1));
    expect(entries.single.changes.join('\n'), contains('桌面快捷方式'));
    expect(entries.single.changes.join('\n'), contains('空白图标'));
    expect(entries.single.changes.join('\n'), contains('自动修复'));
  });

  test('版本历史不存在当前版本时不显示错误的旧版本', () {
    expect(versionHistoryForCurrent('9.9.9'), isEmpty);
  });

  test('二点一十五说明系列继承海报墙过滤和网盘安全边界', () {
    final entries = versionHistoryForCurrent('2.1.15');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('手动匹配'));
    expect(changes, contains('自动继承'));
    expect(changes, contains('海报墙'));
    expect(changes, contains('识别大小'));
    expect(changes, contains('不会修改网盘文件'));
    expect(changes, contains('播放路径'));
  });

  test('二点一十六说明网盘全量海报墙和季度海报', () {
    final entries = versionHistoryForCurrent('2.1.16');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('网盘'));
    expect(changes, contains('海报墙'));
    expect(changes, contains('季度海报'));
    expect(changes, contains('后台扫描'));
    expect(changes, contains('识别大小'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一十七说明按文件夹识别剧名和季度', () {
    final entries = versionHistoryForCurrent('2.1.17');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('文件夹'));
    expect(changes, contains('季度'));
    expect(changes, contains('文件名'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一十八说明每季海报虚拟名称和网盘安全边界', () {
    final entries = versionHistoryForCurrent('2.1.18');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('每一季'));
    expect(changes, contains('海报'));
    expect(changes, contains('剧名'));
    expect(changes, contains('纯数字'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一十九说明修复网盘集数和选集空白', () {
    final entries = versionHistoryForCurrent('2.1.19');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('内嵌中字'));
    expect(changes, contains('集数'));
    expect(changes, contains('选集'));
    expect(changes, contains('自动重新识别'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十说明修复媒体根目录识别', () {
    final entries = versionHistoryForCurrent('2.1.20');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('媒体根目录'));
    expect(changes, contains('高码率'));
    expect(changes, contains('第 3 季'));
    expect(changes, contains('重复卡片'));
    expect(changes, contains('自动重新识别'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十一说明多版本归并手动确认和固定海报尺寸', () {
    final entries = versionHistoryForCurrent('2.1.21');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('多版本'));
    expect(changes, contains('唯一集数'));
    expect(changes, contains('手动确认'));
    expect(changes, contains('海报尺寸'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十二说明重复集号和本地海报尺寸', () {
    final entries = versionHistoryForCurrent('2.1.22');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('同一集'));
    expect(changes, contains('本地海报墙'));
    expect(changes, contains('海报尺寸'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十三说明网盘目录实时刷新和旧资源隐藏', () {
    final entries = versionHistoryForCurrent('2.1.23');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('目录'));
    expect(changes, contains('实时'));
    expect(changes, contains('旧资源'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十五说明夸克播放和季度完整选集', () {
    final entries = versionHistoryForCurrent('2.1.25');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('夸克'));
    expect(changes, contains('播放'));
    expect(changes, contains('当前季度'));
    expect(changes, contains('完整选集'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十六说明夸克播放 Cookie 自动更新', () {
    final entries = versionHistoryForCurrent('2.1.26');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('夸克'));
    expect(changes, contains('播放'));
    expect(changes, contains('Cookie'));
    expect(changes, contains('刷新'));
    expect(changes, contains('官方'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十七说明夸克分段预读和播放状态', () {
    final entries = versionHistoryForCurrent('2.1.27');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('分段预读'));
    expect(changes, contains('4K'));
    expect(changes, contains('重新连接'));
    expect(changes, contains('速度不足'));
    expect(changes, contains('256 MB'));
    expect(changes, contains('不会修改夸克文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十八说明百度官方授权分段播放和私人安装包', () {
    final entries = versionHistoryForCurrent('2.1.28');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('百度网盘'));
    expect(changes, contains('官方授权'));
    expect(changes, contains('分段播放'));
    expect(changes, contains('内置默认 TMDB Key'));
    expect(changes, contains('私人安装包'));
    expect(changes, contains('不会修改百度网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十九说明百度播放修复和本地分季海报', () {
    final entries = versionHistoryForCurrent('2.1.29');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('百度网盘视频'));
    expect(changes, contains('解析或加载失败'));
    expect(changes, contains('本地电视剧'));
    expect(changes, contains('对应季海报'));
    expect(changes, contains('不会修改百度网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十说明百度文件详情兼容和当前版本展示', () {
    final entries = versionHistoryForCurrent('2.1.30');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('百度网盘'));
    expect(changes, contains('文件详情'));
    expect(changes, contains('当前版本'));
    expect(changes, contains('清除缓存'));
    expect(changes, contains('不会修改百度网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十一说明安全存储、日志缓存和Windows集成优化', () {
    final entries = versionHistoryForCurrent('2.1.31');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('TMDB Key'));
    expect(changes, contains('安全存储'));
    expect(changes, contains('日志'));
    expect(changes, contains('缓存'));
    expect(changes, contains('外部播放器'));
    expect(changes, contains('快捷方式'));
    expect(changes, contains('不会删除本地视频'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十二说明本地网盘刮削统一和旧结果保护', () {
    final entries = versionHistoryForCurrent('2.1.32');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('本地与网盘'));
    expect(changes, contains('TMDB'));
    expect(changes, contains('手动'));
    expect(changes, contains('需要确认'));
    expect(changes, contains('断网'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十三说明季度海报、悬停标签和本地刮削对话框', () {
    final entries = versionHistoryForCurrent('2.1.33');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('季度海报'));
    expect(changes, contains('鼠标'));
    expect(changes, contains('TMDB 刮削'));
    expect(changes, contains('重新匹配'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十四说明证书校验、发布流水线和依赖优化', () {
    final entries = versionHistoryForCurrent('2.1.34');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('证书校验'));
    expect(changes, contains('发布流水线'));
    expect(changes, contains('依赖'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十五说明安装版本检查和安装包验证', () {
    final entries = versionHistoryForCurrent('2.1.35');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('已安装版本'));
    expect(changes, contains('签名 MSIX'));
    expect(changes, contains('清单版本'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一四十四说明夸克转存目录与扫描联动', () {
    final entries = versionHistoryForCurrent('2.1.44');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('转存目录'));
    expect(changes, contains('媒体根目录'));
    expect(changes, contains('扫描'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十五说明夸克旧转存目录扫描自愈', () {
    final entries = versionHistoryForCurrent('2.1.45');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('默认转存目录'));
    expect(changes, contains('下次扫描时自动补齐'));
    expect(changes, contains('不记录 Cookie'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十六继续修复夸克默认转存目录漏扫', () {
    final entries = versionHistoryForCurrent('2.1.46');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('默认转存目录'));
    expect(changes, contains('自动检查并补齐'));
    expect(changes, contains('不记录 Cookie'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十七修复夸克旧 ID 和取消状态', () {
    final entries = versionHistoryForCurrent('2.1.47');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('默认转存目录'));
    expect(changes, contains('旧远程 ID'));
    expect(changes, contains('不再残留“正在扫描”'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十八收敛 Windows 网盘入口和 Anime4K', () {
    final entries = versionHistoryForCurrent('2.1.48');
    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    expect(changes, contains('百度'));
    expect(changes, contains('Windows'));
    expect(changes, contains('Anime4K'));
    expect(changes, contains('不会修改或删除'));
  });

  testWidgets('二点一七更新弹窗明确显示自定义剧名安全边界', (tester) async {
    final entries = versionHistoryForCurrent('2.1.7');

    expect(entries.single.isPrerelease, isTrue);
    expect(entries.single.releaseLabel, '测试版');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.7  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('TMDB'));
    expect(entries.single.changes.join('\n'), contains('网盘'));
    expect(entries.single.changes.join('\n'), contains('修改剧名'));
    expect(entries.single.changes.join('\n'), contains('不会重命名'));
    for (final change in entries.single.changes) {
      expect(find.textContaining(change), findsOneWidget);
    }
  });

  testWidgets('二点一八更新弹窗说明夸克直连播放修复', (tester) async {
    final entries = versionHistoryForCurrent('2.1.8');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.8  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('夸克'));
    expect(entries.single.changes.join('\n'), contains('直连'));
    expect(entries.single.changes.join('\n'), contains('自动刷新'));
    expect(entries.single.changes.join('\n'), contains('OpenList'));
  });

  testWidgets('二点一九更新弹窗说明使用夸克专用播放地址', (tester) async {
    final entries = versionHistoryForCurrent('2.1.9');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.9  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('夸克'));
    expect(entries.single.changes.join('\n'), contains('专用播放接口'));
    expect(entries.single.changes.join('\n'), contains('最高可用清晰度'));
    expect(entries.single.changes.join('\n'), contains('下载直链'));
  });

  testWidgets('二点一十更新弹窗说明季目录可进行 TMDB 刮削', (tester) async {
    final entries = versionHistoryForCurrent('2.1.10');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.10  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('TMDB'));
    expect(entries.single.changes.join('\n'), contains('季目录'));
    expect(entries.single.changes.join('\n'), contains('单集文件名'));
    expect(entries.single.changes.join('\n'), contains('当前目录'));
  });

  testWidgets('二点一十一更新弹窗说明 TMDB 匹配可先确认', (tester) async {
    final entries = versionHistoryForCurrent('2.1.11');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.11  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('搜索词'));
    expect(entries.single.changes.join('\n'), contains('候选'));
    expect(entries.single.changes.join('\n'), contains('不会修改网盘文件'));
    expect(entries.single.changes.join('\n'), contains('批量刮削'));
  });

  testWidgets('二点一十二更新弹窗说明网盘沉浸式海报卡', (tester) async {
    final entries = versionHistoryForCurrent('2.1.12');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.12  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('沉浸式大海报卡片'));
    expect(entries.single.changes.join('\n'), contains('真实网盘名称'));
    expect(entries.single.changes.join('\n'), contains('已确认的字幕状态'));
    expect(entries.single.changes.join('\n'), contains('不会修改任何网盘文件'));
  });

  testWidgets('二点一十三更新弹窗说明过滤发布规格尾缀', (tester) async {
    final entries = versionHistoryForCurrent('2.1.13');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.13  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('2160p'));
    expect(entries.single.changes.join('\n'), contains('HEVC'));
    expect(entries.single.changes.join('\n'), contains('DDP 5.1'));
    expect(entries.single.changes.join('\n'), contains('不会修改网盘文件名'));
  });

  testWidgets('二点一十四更新弹窗说明来源级自动批量整理', (tester) async {
    final entries = versionHistoryForCurrent('2.1.14');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.14  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('自动整理当前来源'));
    expect(entries.single.changes.join('\n'), contains('递归发现'));
    expect(entries.single.changes.join('\n'), contains('歧义资源保持原名'));
    expect(entries.single.changes.join('\n'), contains('不会修改网盘文件'));
  });

  test('历史版本默认保持正式版兼容语义', () {
    const entry =
        VersionHistory(version: '1.0.0', date: '2026-01-01', changes: []);

    expect(entry.isPrerelease, isFalse);
    expect(entry.releaseLabel, '正式版');
  });
}
