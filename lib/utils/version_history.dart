import 'package:kanyingyin/platform/app_platform.dart';

part 'version_history/android_release_summaries.dart';
part 'version_history/changelog_2_1_early.dart';
part 'version_history/changelog_2_1_late.dart';
part 'version_history/changelog_stable_legacy.dart';

class VersionHistory {
  final String version;
  final String date;
  final List<String> changes;
  final bool isPrerelease;

  String get releaseLabel => isPrerelease ? '测试版' : '正式版';

  const VersionHistory({
    required this.version,
    required this.date,
    required this.changes,
    this.isPrerelease = false,
  });
}

/// 应用内更新历史列表（最新在前）。
/// 当前版本条目保留在本文件内：test/version_consistency_test.dart
/// 以文本方式断言本声明与当前版本条目的位置；其余条目按发布时间连续
/// 区段拆分到 part 文件，展开顺序与原列表完全一致，不得重排。
const List<VersionHistory> versionHistoryList = [
  VersionHistory(
    version: '1.0.14',
    date: '2026-09-06',
    changes: [
      'Windows 网盘季度卡片新增“重新刮削本季”，只更新当前季资料和封面；整剧更新或更换 TMDB 剧目时会确认影响范围',
      '修复跨目录归并和多季同时更新时季度海报互相覆盖的问题；失败时保留原资料和旧封面',
      'Windows 清理缓存会拒绝数据目录重合、危险目录以及混入视频或数据库的目录，避免误删重要数据',
      'Windows 和 Android 的网盘视频隐藏、恢复和来源移除后，分类页、网盘页与隐藏管理列表保持同步',
      '修复首次网盘加载失败后点击“重试”无效的问题，并避免重复请求和返回页面后重复加载',
      'Android 手机和平板继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
    ],
  ),
  VersionHistory(
    version: '2.1.206',
    date: '2026-09-06',
    isPrerelease: true,
    changes: [
      '网盘季度卡片新增“重新刮削本季”，只更新当前季资料和封面，不再连带更新其他季',
      '整部剧重新刮削与更换 TMDB 剧目需要确认影响范围，避免单季操作意外覆盖整剧',
      '修复跨目录归并时季度海报互相覆盖的问题；多个季度同时更新时分别保留结果',
      '季度资料或海报请求失败时保留原资料和旧封面，加载提示只作用于当前季',
      '本轮仅交付 Windows 测试版 EXE；Android 手机仅同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.205',
    date: '2026-09-05',
    isPrerelease: true,
    changes: [
      '修复数据目录与缓存目录重合时清理缓存可能误删数据库的问题；危险目录或混入视频、数据库的缓存目录会明确拒绝操作',
      '网盘视频隐藏或恢复后，分类页、网盘页和隐藏管理列表保持同步，连续隐藏不再覆盖已有记录',
      '移除最后一个网盘来源后，分类页同步清空对应筛选和视频；读取失败时保留已有内容',
      '修复首次网盘加载失败后点击“重试”无效的问题，避免重复请求和返回页面后重复加载',
      '本轮仅交付 Windows 测试版 EXE；Android 手机仅同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频；缓存清理只在确认后执行',
    ],
  ),
  VersionHistory(
    version: '2.1.204',
    date: '2026-09-04',
    isPrerelease: true,
    changes: [
      '抽取超分辨率确认弹窗，保持确认、取消和下次不再询问行为一致',
      'Windows 媒体库、分类和网盘资源页继续保留加载状态与播放入口；Android 手机和平板版本配置保持一致',
      '本轮仅交付 Windows 测试版 EXE，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
    ],
  ),
  VersionHistory(
    version: '1.0.13',
    date: '2026-09-01',
    changes: [
      'Windows 和 Android 首次加载、刷新时显示与最终布局对应的海报或列表骨架，并保留已有内容，减少空白等待',
      '本地和网盘来源移除、失效来源清理、清空观看历史都需要确认；失败时保留对象并支持重试',
      '全屏切换过渡更平滑，网盘视频不再显示顶部常态读取速度；底部网速、预缓冲和低速提示继续保留',
      '手机和平板取消海报墙常驻信息浮窗，点击资源进入媒体详情和选集界面',
      '修复分类详情和网盘选集面板中 4K、来源、编码等技术规格标签缺失的问题，优先使用资源已保存的结构化标签',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
    ],
  ),
  ..._changelog21LateHistory,
  ..._changelog21EarlyHistory,
  ..._changelogStableLegacyHistory,
  // 2.1.139（Android TV 焦点修复）历史上追加在列表末尾，保持原位置。
  VersionHistory(
    version: '2.1.139',
    date: '2026-08-07',
    changes: [
      '修复 Android TV 遥控器方向键焦点无法移动到侧边导航栏的问题',
      'Android TV 在桌面布局中增加焦点遍历策略，支持左右键在导航栏和内容区之间切换',
      '修复本地媒体库文件夹下拉菜单展开时，按返回键误弹退出对话框的问题',
      '文件夹下拉菜单现在可以用 ESC 键或返回键正常关闭',
      '修复 Android TV 退出确认对话框中按返回键直接退出应用的问题',
      '退出确认弹窗必须点击"退出"按钮才能退出应用，按返回键会关闭弹窗',
      '更新测试用例以匹配新的退出交互行为',
    ],
  ),
];

List<VersionHistory> versionHistoryForCurrent(
  String currentVersion, {
  AppPlatformKind? platform,
}) {
  if (currentVersion == '1.0.14' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '1.0.10',
        date: '2026-09-06',
        changes: [
          '手机和平板的网盘季度卡片新增“重新刮削本季”，只更新当前季资料和封面；整剧更新或更换 TMDB 剧目时会确认影响范围',
          '修复跨目录归并和多季同时更新时季度海报互相覆盖的问题；资料或海报请求失败时保留原内容',
          '网盘视频隐藏、恢复和来源移除后，分类页、网盘页与隐藏管理列表保持同步；首次加载失败后可以正常重试',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.204' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '2.1.204',
        date: '2026-09-04',
        isPrerelease: true,
        changes: [
          '抽取超分辨率确认弹窗，保持确认、取消和下次不再询问行为一致',
          '本轮仅交付 Windows 测试版 EXE，不构建 Android TV 安装包',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
        ],
      ),
    ];
  }
  if (currentVersion == '1.0.13' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '1.0.9',
        date: '2026-09-01',
        changes: [
          '手机和平板取消海报墙常驻信息浮窗，点击资源进入媒体详情和选集界面，再从详情查看简介、技术规格和资源信息后播放',
          '修复分类详情和网盘选集面板中 4K、来源、编码等技术规格标签缺失的问题，优先使用资源已保存的结构化标签',
          '首次加载和刷新时保留已有内容并显示局部加载状态；来源移除、失效来源清理和清空历史需要确认，失败时支持重试',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.203' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_android203Prerelease];
  }
  if (currentVersion == '2.1.202' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidCurrentPrerelease];
  }
  if (currentVersion == '2.1.201' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_android201Prerelease];
  }
  if (currentVersion == '2.1.200' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_android200Prerelease];
  }
  if (currentVersion == '2.1.199' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_android2199Prerelease];
  }
  if (currentVersion == '1.0.12' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidNinthRelease];
  }
  if (currentVersion == '1.0.11' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidEighthRelease];
  }
  if (currentVersion == '1.0.10' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidSeventhRelease];
  }
  if (currentVersion == '1.0.9' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidSixthRelease];
  }
  if (currentVersion == '1.0.8' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidFifthRelease];
  }
  if (currentVersion == '2.1.158' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidFifthRelease];
  }
  if (currentVersion == '1.0.7' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidFifthRelease];
  }
  if (currentVersion == '1.0.6' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidFourthRelease];
  }
  if (currentVersion == '1.0.5' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidThirdRelease];
  }
  if (currentVersion == '2.1.103' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      _androidAdaptiveQuarkSystemBarsPrerelease,
    ];
  }
  if (currentVersion == '2.1.102' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidImmersiveTrueHdPrerelease];
  }
  if (currentVersion == '2.1.101' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidDiagnosticLogSharePrerelease];
  }
  if (currentVersion == '1.0.4' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidSecondRelease];
  }
  if (currentVersion == '2.1.98' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidAnime4kShaderListRelease];
  }
  if (currentVersion == '2.1.97' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidCloudHighThroughputRelease];
  }
  if (currentVersion == '2.1.96' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidLogAnime4kRelease];
  }
  if (currentVersion == '2.1.95' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidNetworkRelease];
  }
  if (currentVersion == '1.0.3' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidFirstRelease];
  }
  return versionHistoryList
      .where((entry) => entry.version == currentVersion)
      .take(1)
      .toList(growable: false);
}
