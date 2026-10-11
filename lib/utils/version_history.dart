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
    version: '1.0.17',
    date: '2026-10-12',
    changes: [
      'Windows 媒体库和个人网盘支持收藏、待看、自定义合集以及独立的已看状态和观看进度，来源改名或重新分组后继续保留记录',
      '播放器支持读取内嵌章节、保存手动书签、设置片头片尾标记，并沿用同一作品跨集的音轨和字幕偏好',
      '加密备份扩展收藏、观看历史、书签、播放进度和选轨偏好，支持目录与网盘来源重新对应，导入失败时回滚',
      '媒体库分类支持动漫、电视剧和电影分开归类，动画电影可选择电影、动漫或两者；分类可信度、题材和自定义标签分开管理，并提供待确认检查入口',
      'TMDB 题材标签默认直接采用，主分类在证据不足或冲突时确认；刷新和重新刮削保留人工分类、题材和标签覆盖，来源界面沿用来源剧名',
      '网盘季度卡片支持“重新刮削本季”，只更新当前季资料和封面，并保留手动图片选择',
      '保留本地原名称、清晰度、来源和编码等技术标签及 4K 识别，并继续支持海报、背景图、季度海报和单集剧照的选择与缓存刷新',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和图片文件',
    ],
  ),
  VersionHistory(
    version: '2.1.226',
    date: '2026-10-12',
    isPrerelease: true,
    changes: [
      '题材标签默认直接采用 TMDB 刮削结果，剧情、喜剧等多题材不再要求逐项确认',
      '仅电影、动漫、电视剧等主分类在证据不足或存在冲突时进入待确认，保留明确的人工分类覆盖',
      '分类编辑器和分类检查会把题材标签与主分类分开显示，刷新和重新刮削继续尊重已有人工覆盖',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.225',
    date: '2026-10-12',
    isPrerelease: true,
    changes: [
      '本地媒体库和个人网盘媒体库的剧集菜单统一提供“编辑分类与标签”，分类页海报菜单去除重复入口',
      'TMDB 操作按匹配状态合并：未匹配显示“TMDB 刮削”，已匹配显示“重新匹配”，待确认仍保留手动确认',
      '网盘媒体库仅在存在可分类剧集时显示分类与标签入口，避免对单个视频展示无效操作',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.224',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '动漫与电视剧分开归类，动画电影可自主选择电影、动漫或两者',
      '分类可信度支持保守、标准和全手动，多标签由你选择，信息不足的作品进入待确认',
      '分类、题材和自定义标签分开管理，可明确清空或恢复自动，刷新与重新刮削保留人工选择',
      '新增分类检查与待确认入口，分类选择和可信度设置可随加密备份恢复',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.223',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '修复分类海报在来源剧名后额外追加 S01 等季号的问题',
      '动漫、电视剧和电影卡片原样沿用对应媒体库来源剧名，保留来源本身的季度名称',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.222',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '作品剧名以对应来源界面为准，媒体库、详情和播放器沿用同一名称',
      '观看历史和继续观看同步当前来源剧名，来源不可用时保留已有记录和播放进度',
      '修复来源改名期间媒体库可能保留旧标题的问题，保留来源本身的季度名称',
      '作品改名后继续沿用音轨和字幕偏好，兼容原有记录',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.221',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '修复页面切换前半程内容不显示的问题，导航选中状态及时跟随页面',
      '设置页沿用统一的页面转场，减少重复淡入带来的停顿',
      '选集面板可连续展开和收起，中途反向操作不会被旧的关闭任务打断',
      '优化全屏进出与窗口缩放的衔接，最大化窗口退出全屏时也保持过渡',
      '全屏切换期间合并重复操作，失败时保留正确状态，视频尺寸随播放区域变化',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.220',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '每个视频可手动设置片头/片尾区间，时间轴显示色带、起止刻度和标签；仅显示标记，不自动跳过或切集',
      '本地时间轴缩略图按约十秒采样，坏图自动重建、文件变化后失效；缩小后存入应用缓存，每个视频最多保留 20 张',
      '已看和观看进度独立保存，支持手动标记、已看/未看筛选和卡片进度，清空历史不会清除已看记录',
      '手动选轨优先，同一作品跨集沿用语言偏好；播放设置可选择全局音轨和字幕语言，不抢占外置字幕',
      '加密备份增加片头片尾、已看/进度和选轨偏好，兼容旧配置包并支持目录、来源重新对应',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.219',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '本地目录断盘或读取失败时保留旧索引，恢复后再确认文件变更',
      '作品改名、重新匹配或分组合并后继续保留收藏、待看和合集，无法确认的记录可手动关联',
      '加密备份增加收藏、待看、合集、书签和观看历史，支持旧配置包、目录重新对应及导入失败回滚',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.218',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '播放器支持读取内嵌章节和保存手动书签，书签与视频详情弹窗切换更可靠',
      '本地视频支持时间轴缩略图预览，快速拖动时逐个生成截图，退出或关闭预览后不再保存过期结果',
      '每个视频最多保留 20 张时间轴缓存，低内存模式关闭预览，生成失败时继续使用普通进度条',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.217',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '播放器可读取本地视频中的内嵌章节，也可以继续使用手动书签',
      '本地视频拖动进度条时按需生成时间轴缩略图，最多保留每个视频 20 张缓存，生成失败会自动回退普通进度条',
      '时间轴缩略图只保存在看影音缓存目录中，不会上传或修改本地及个人网盘原始视频',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.216',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '媒体库支持收藏、待看和自定义合集筛选，状态保存在看影音专属数据目录中',
      '本地媒体重扫会展示新增、更新、移除和失败变更，播放器可为本地与个人网盘视频保存手动书签',
      'TMDB 详情补充主演、导演和相似作品，并在媒体详情中展示',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
  VersionHistory(
    version: '2.1.215',
    date: '2026-10-11',
    isPrerelease: true,
    changes: [
      '本地媒体索引支持保存已核对的原名称候选，并从原名称补充捕捉清晰度、来源和编码等技术标签',
      '本地媒体重扫、文件改名迁移以及海报卡片、详情页和选集页都会保留并使用这些标签',
      '继续识别 2160p、3840x2160 和 UHD 等常见 4K 写法，并汇总显示多个文件中的最高规格',
      '本轮仅交付 Windows 测试版 EXE；Android 手机同步版本配置，不构建 Android TV 安装包',
      '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
    ],
  ),
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
  if (currentVersion == '1.0.17' && platform == AppPlatformKind.android) {
    return const <VersionHistory>[
      VersionHistory(
        version: '1.0.13',
        date: '2026-10-12',
        changes: [
          '手机和平板的本地媒体库和个人网盘支持来源剧名、清晰度、来源和编码等信息，并继续识别 4K 规格',
          '支持收藏、待看、自定义合集以及独立的已看状态和观看进度，来源改名或重新分组后继续保留记录',
          '播放器支持内嵌章节和手动书签，可设置片头片尾标记，并沿用同一作品跨集的音轨和字幕偏好',
          '加密备份覆盖收藏、观看历史、书签、播放进度、选轨偏好以及目录和网盘来源重新对应，导入失败时回滚',
          '手机和平板支持动漫、电视剧和电影分类、动画电影多分类、分类可信度、题材与自定义标签分离，以及待确认检查入口',
          'TMDB 题材标签默认直接采用，主分类在证据不足或冲突时确认；刷新和重新刮削保留人工分类与标签覆盖，媒体界面沿用来源剧名',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和图片文件',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.226' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.226',
        date: '2026-10-12',
        isPrerelease: true,
        changes: [
          '题材标签默认直接采用 TMDB 刮削结果，剧情、喜剧等多题材不再要求逐项确认',
          '仅电影、动漫、电视剧等主分类在证据不足或存在冲突时进入待确认，保留明确的人工分类覆盖',
          '分类编辑器和分类检查会把题材标签与主分类分开显示，刷新和重新刮削继续尊重已有人工覆盖',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.225' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.225',
        date: '2026-10-12',
        isPrerelease: true,
        changes: [
          '本地媒体库和个人网盘媒体库的剧集菜单统一提供“编辑分类与标签”，分类页海报菜单去除重复入口',
          'TMDB 操作按匹配状态合并，未匹配执行刮削，已匹配执行重新匹配，待确认仍可手动确认',
          '网盘媒体库仅在存在可分类剧集时显示分类与标签入口，避免对单个视频展示无效操作',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.224' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.224',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '动漫与电视剧分开归类，动画电影可自主选择电影、动漫或两者',
          '分类可信度支持保守、标准和全手动，多标签由你选择，信息不足的作品进入待确认',
          '分类、题材和自定义标签分开管理，可明确清空或恢复自动，刷新与重新刮削保留人工选择',
          '新增分类检查与待确认入口，分类选择和可信度设置可随加密备份恢复',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.223' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.223',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '修复分类海报在来源剧名后额外追加 S01 等季号的问题',
          '手机和平板的分类卡片原样沿用对应媒体库来源剧名，保留来源本身的季度名称',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '继续支持字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.222' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.222',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板的媒体库、详情、播放器与观看历史沿用对应来源界面的剧名',
          '来源改名后继续保留播放进度与音轨、字幕偏好，来源不可用时保留已有历史记录',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '继续支持字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.221' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.221',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板的导航选中状态及时跟随页面，设置内容沿用页面转场',
          '选集面板连续展开、收起和中途反向操作时衔接更稳定',
          '全屏和方向变化共用切换状态，视频尺寸随播放区域变化',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '继续支持字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.220' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
          version: '2.1.220',
          date: '2026-10-11',
          isPrerelease: true,
          changes: [
            '手机和平板播放器支持手动片头/片尾标记，已看和观看进度独立保存',
            '同一作品跨集沿用音轨、字幕语言偏好，播放设置可选择全局语言，不抢占外置字幕',
            '加密备份增加片头片尾、已看/进度和选轨偏好，兼容旧配置包',
            '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
            '继续支持后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
            '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
          ]),
    ];
  }
  if (currentVersion == '2.1.219' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.219',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板媒体库读取失败时保留旧索引，收藏、待看和合集支持分组关联',
          '加密备份增加收藏、待看、合集、书签和观看历史，兼容旧配置包',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '继续支持字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.218' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.218',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板播放器支持内嵌章节和手动书签，修正书签与视频详情弹窗的切换',
          '本轮仅同步 Android 手机版本配置，不交付 Android 安装包',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.217' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.217',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板播放器可读取本地视频中的内嵌章节，也可以继续使用手动书签',
          '本轮同步播放器章节和书签版本配置，不交付 Android 安装包',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.216' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.216',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板支持收藏、待看和自定义合集筛选，并保存在看影音专属数据目录中',
          '本地媒体重扫会展示新增、更新、移除和失败变更，播放器可保存手动书签',
          'TMDB 详情补充主演、导演和相似作品，并在媒体详情中展示',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
  if (currentVersion == '2.1.215' && platform == AppPlatformKind.android) {
    return const [
      VersionHistory(
        version: '2.1.215',
        date: '2026-10-11',
        isPrerelease: true,
        changes: [
          '手机和平板支持使用已核对的媒体原名称补充捕捉清晰度、来源和编码等技术标签',
          '本地媒体重扫、文件改名迁移以及媒体卡片和详情页会保留并使用这些标签',
          '继续识别 2160p、3840x2160 和 UHD 等常见 4K 写法，并汇总显示多个文件中的最高规格',
          '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
          '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频',
        ],
      ),
    ];
  }
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
