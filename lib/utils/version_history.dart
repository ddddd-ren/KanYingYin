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
    version: '1.0.16',
    date: '2026-10-11',
    changes: [
      '本地视频海报卡片补充清晰度、来源和编码标签；读取媒体信息后会保存视频尺寸与时长',
      '继续识别 2160p、3840x2160 和 UHD 等常见 4K 写法，并汇总显示多个文件中的最高规格',
      '网盘剧集支持按来源目录和发布规格切换版本，缺集可共享同季其他版本并保留多个候选',
      'Windows 网盘季度卡片继续支持“重新刮削本季”，只更新当前季资料和封面',
      '本地媒体库和个人网盘支持选择海报、背景图、季度海报和单集剧照，重新刮削会保留手动选择',
      '修复换图后旧缓存或旧显示结果未及时刷新的问题，连续替换后会保存并立即刷新',
      '完善图片选择、保存、索引同步和显示日志；本次更新不会修改、删除、改名或移动原始视频',
      '继续保护数据目录与缓存目录，缓存清理不会误删媒体库数据库',
      'Windows 和 Android 手机和平板继续支持原有播放、字幕和网盘能力',
    ],
  ),
  VersionHistory(
    version: '2.1.214',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '修复本地媒体库和个人网盘更换刮削图片后显示结果与所选图片不一致的问题',
      '支持连续更换海报、季度海报、背景图和单集剧照，并在保存后立即刷新',
      '完善图片选择、保存、索引同步和显示日志，便于定位换图链路问题',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频；换图只更新本地资料与显示索引',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
    ],
  ),
  VersionHistory(
    version: '2.1.213',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '修复替换网盘海报后仍显示旧缓存的问题，总海报和季度海报会立即刷新',
      '网盘海报替换结果会同步到媒体索引，重新进入页面后仍保留手动选择',
      '本地媒体库和个人网盘继续支持选择海报、背景图、季度海报和单集剧照',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.212',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      'TMDB 刮削完成后可为剧集选择海报、背景图、季度海报和单集剧照',
      '本地媒体库和个人网盘详情页支持浏览图片候选，点击图片即可保存选择',
      '重新刮削会保留手动选择，也可以随时恢复海报、背景图、季度海报或剧照默认值',
      '换图只更新本地刮削记录和显示索引，不修改网盘原始视频文件',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.210',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '网盘剧集选集支持按来源目录和发布规格切换版本1、版本2，重复剧集不再混在一份列表里',
      '某个版本缺集时可使用同季其他版本的文件补齐，并标注共享来源，保留同集的多个候选',
      '网盘资源页和媒体分类页均支持版本选择，播放及切换剧集沿用选中的版本',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.209',
    date: '2026-10-10',
    isPrerelease: true,
    changes: [
      '本地视频海报卡片现在会复用媒体库索引中的清晰度、来源和编码信息，显示 4K、2K、1080P 等技术标签',
      '点击“读取媒体信息”后，视频宽高和时长会保存到本地媒体库索引，重新进入目录仍可显示标签',
      '继续识别 2160p、3840x2160 和 UHD 等常见 4K 写法，并汇总显示多个文件中的最高规格',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.208',
    date: '2026-10-10',
    isPrerelease: true,
    changes: [
      '本地视频海报和详情现在也会按文件名与已读取的媒体信息识别 4K、2K、1080P 等清晰度标签',
      '补充识别 2160p、3840x2160 和 UHD 等常见 4K 写法，多个文件会汇总显示最高清晰度',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '1.0.15',
    date: '2026-10-01',
    changes: [
      '网盘页面在窄屏下自动分成两行，添加、管理、刷新和更多操作保持可见；宽屏布局保持原有排列',
      '网盘来源名称过长时自动省略，展开选择菜单仍可查看完整名称',
      '网盘播放速度改为连续采样确认后再提示持续低速，减少短时网络抖动造成的误报',
      '速度判断使用网盘 Range 实际吞吐和首字节耗时，不再把本机网卡链路速率当作网盘速度',
      '播放日志补充来源、分段、吞吐、缓存秒数和自适应档位变化，便于导出诊断日志排查',
      'Windows 和 Android 手机和平板继续支持本地媒体库、个人网盘及原有播放能力',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.207',
    date: '2026-09-06',
    isPrerelease: true,
    changes: [
      '网盘工具栏在窄屏下自动分成两行，添加、管理、刷新和更多操作保持可见；宽屏布局不变',
      '网盘来源名称较长时自动省略显示，展开选择菜单可查看完整名称',
      '保留“重新刮削本季”的独立更新和整剧更新确认，失败时保留原资料和旧封面',
      '本轮仅交付 Windows 测试版 EXE；Android 手机仅同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
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
  if (currentVersion == '2.1.214' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.214',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '修复本地媒体库和个人网盘更换刮削图片后显示结果与所选图片不一致的问题',
          '支持连续更换海报、季度海报、背景图和单集剧照，并在保存后立即刷新',
          '换图只更新本地资料与显示索引，不修改、删除、改名或移动原始视频',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.213' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.213',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '修复替换网盘海报后仍显示旧缓存的问题，总海报和季度海报会立即刷新',
          '网盘海报替换结果会同步到媒体索引，重新进入页面后仍保留手动选择',
          '本地媒体库和个人网盘继续支持选择海报、背景图、季度海报和单集剧照',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.212' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.212',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          'TMDB 刮削完成后可为剧集选择海报、背景图、季度海报和单集剧照',
          '本地媒体库和个人网盘详情页支持浏览图片候选，点击图片即可保存选择',
          '重新刮削会保留手动选择，也可以恢复各级图片的默认值',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.210' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.210',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '网盘资源页和媒体分类页支持按来源目录和发布规格选择剧集版本',
          '同季其他版本可共享缺少的剧集，并显示共享来源，播放及切换剧集沿用选中的版本',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.209' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '2.1.209',
        date: '2026-10-10',
        isPrerelease: true,
        changes: [
          '本地视频海报卡片会复用媒体库索引中的清晰度、来源和编码信息，显示 4K、2K、1080P 等技术标签',
          '点击“读取媒体信息”后，视频宽高和时长会保存到本地媒体库索引，重新进入目录仍可显示标签',
          '2160p、3840x2160 和 UHD 等常见 4K 写法会统一识别，作品汇总显示最高规格',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '1.0.16' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '1.0.12',
        date: '2026-10-11',
        changes: [
          '手机和平板的本地视频海报卡片支持清晰度、来源和编码标签；读取媒体信息后会保留视频尺寸与时长',
          '手机和平板继续识别 2160p、3840x2160 和 UHD 等常见 4K 写法，并汇总显示多个文件中的最高规格',
          '网盘剧集支持按来源目录和发布规格选择版本，缺集可共享同季其他版本的文件，并保留多个候选',
          '手机和平板支持选择海报、背景图、季度海报和单集剧照；重新刮削保留手动选择，换图后立即刷新显示',
          '修复网盘海报旧缓存和本地、网盘换图结果不一致的问题，图片选择与媒体索引保持同步',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
        ],
      ),
    ];
  }
  if (currentVersion == '1.0.15' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '1.0.11',
        date: '2026-10-01',
        changes: [
          '手机和平板的网盘页面支持窄屏两行工具栏，来源名称过长时省略显示并可在菜单中查看完整名称',
          '网盘播放速度改为连续采样确认后再提示持续低速，并按实际 Range 吞吐和首字节耗时判断',
          '播放日志补充来源、分段、吞吐、缓存秒数和自适应档位变化，便于导出诊断日志排查',
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
