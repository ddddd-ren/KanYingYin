part of '../version_history.dart';

/// Android 各正式版/测试版的命名更新说明常量，仅供 [versionHistoryForCurrent] 使用。
const VersionHistory _androidFirstRelease = VersionHistory(
  version: '1.0.0',
  date: '2026-07-30',
  changes: [
    'Android 首次正式发布：支持 Android 7.0 及以上设备，使用系统存储访问框架选择一个或多个本地媒体目录，应用不会申请或扫描全盘存储',
    '本地媒体库支持递归扫描视频、字幕和媒体信息，保留 content URI；授权失效时保留已有索引，重新授权后可继续使用',
    '播放器支持 MediaCodec 硬件解码、自动或软件解码切换、GPU 渲染、中文字体字幕、内嵌与外挂字幕、PGS 图形字幕、配音和音轨选择、选集与播放进度恢复',
    '支持后台播放、前台播放通知、系统画中画、亮度调节、截图、外部播放器和横屏播放；平板进入应用后使用双向横屏，退出全屏不会强制切回竖屏',
    '改进手机和平板的黑屏、返回、TrueHD 音轨、字幕显示、跳播预读和视频硬解兼容性；硬解打开失败时自动重载视频轨并回退软件解码',
    '支持个人网盘媒体播放和 TMDB 资料、海报、背景图与季集信息；没有 TMDB Key 或断网时，本地扫描和已缓存资料仍可使用',
    'Android 使用系统 WebView 完成账号设备验证，仅允许官方 HTTPS 页面，阻止下载、新窗口、不安全页面和权限请求，验证成功后自动继续登录',
    '应用数据、字幕缓存和缩略图保存在看影音专属目录；安装和更新不会修改、删除或转码本地及网盘原始视频和字幕文件',
  ],
);

const VersionHistory _androidSecondRelease = VersionHistory(
  version: '1.0.1',
  date: '2026-08-02',
  changes: [
    'Android 1.0.1 正式版综合近期移动端更新，继续支持本地媒体库、个人网盘、字幕、音轨、后台播放和系统画中画',
    '夸克与百度网盘高码率视频读取可使用最多六路连接和五路后台预取，前向预取窗口扩大到 40 MiB；缓存仍限制为 128 MiB，低内存模式降到 64 MiB',
    '修复自动 GPU 渲染器无法正确启用 Anime4K，以及多条着色器路径可能被误当成一个文件名的问题；着色器会按顺序加载，失败时保留普通播放',
    '运行记录支持复制单条完整脱敏日志；关于页新增“更新说明”，可随时查看 Android 当前版本内容',
    '修复设置页面禁用的单选项缺少回调时可能构建失败的问题，不可用选项现在会安全保持禁用',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidThirdRelease = VersionHistory(
  version: '1.0.2',
  date: '2026-08-03',
  changes: [
    'Android 1.0.2 正式版综合 2.1.101 至 2.1.103 的移动端功能更新',
    '诊断日志页面支持导出完整脱敏诊断包，并通过系统分享面板发送或保存；网盘凭据、Token、请求头和远程媒体完整地址不会进入导出内容',
    '为只有 TrueHD/MLP 音轨的视频提供软件解码和立体声输出，同时继续保留 MediaCodec 视频硬件解码',
    '横屏播放器保持沉浸显示，旋转、恢复前台或重新获得焦点后会继续隐藏系统栏；普通页面的状态栏和底部手势区与界面同色',
    '夸克原画播放会根据缓存压力自适应提速，最多使用八路读取和七路后台预取，临时缓存上限为 192 MiB；重新连接后会先回到稳健档位，缓存恢复后再按实际压力提速',
    '百度及迅雷网盘读取策略保持不变',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidFourthRelease = VersionHistory(
  version: '1.0.3',
  date: '2026-08-06',
  changes: [
    'Android 新增电影、动漫和电视剧分类入口，可直接浏览本地与个人网盘资源',
    '剧集支持逐视频匹配 TMDB 季度和集数，选集显示“当前剧名 S01E01 TMDB 集名”',
    'TMDB 集名只用于补充单集名称，不会覆盖用户设置的剧名，也不会修改本地文件、网盘路径、字幕关联或播放入口',
    '多季度、多版本和不同目录的作品会按统一规则归并，并保留对应季度海报、集数和播放资源',
    'TMDB 请求使用共享缓存并合并重复请求；没有 TMDB Key、断网或请求失败时，扫描、浏览和播放仍可使用',
    'Android 继续支持字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidFifthRelease = VersionHistory(
  version: '1.0.4',
  date: '2026-08-09',
  changes: [
    '改善剧场版 TMDB 匹配和电影、动漫、电视剧分类，减少作品被归入错误入口的问题',
    '动画电影可以同时显示在动漫和电影入口，动画电视剧可以同时显示在动漫和电视剧入口',
    '云盘外挂字幕现在显示原始文件名，不再显示内部缓存名称',
    '修复部分 ASS 字幕因文件头包含重复 UTF-8 BOM 而无法加载的问题，已有错误字幕缓存会在播放前自动修复',
    '修复作品子目录中的裸集号被拆成不同版本，分集可以按真实集数归入同一作品',
    '修复网盘搜索无匹配结果时误报“视频已隐藏”，现在会明确提示“没有找到匹配的视频”',
    '没有 TMDB Key、断网或请求失败时，本地扫描、媒体库浏览和播放仍可继续',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件，也不会改变远程路径和播放 ID',
  ],
);

const VersionHistory _androidSixthRelease = VersionHistory(
  version: '1.0.5',
  date: '2026-08-24',
  changes: [
    'Android 1.0.5 正式版支持高刷新率界面、实时网速显示和当前视频低速提示关闭',
    '季度目录和逐集名称识别更加稳定，手动匹配结果会保留；电影、动漫和电视剧分类继续按媒体类型展示',
    'OpenList 使用账号或令牌时要求 HTTPS；网盘海报优先使用稳定缓存，减少重复加载和白色占位',
    '选集和播放器会显示 4K、杜比视界、HDR10+、HDR 和杜比全景声等媒体技术标签',
    'TMDB 海报暂时获取失败时仍保留标题、简介、评分和季集资料，不影响扫描、浏览和播放',
    '本次更新不会修改或删除，也不会改名、移动本地及个人网盘原始视频和字幕',
  ],
);

const VersionHistory _androidSeventhRelease = VersionHistory(
  version: '1.0.6',
  date: '2026-08-25',
  changes: [
    '手机和平板可以根据视频文件名识别流媒体来源、码率、帧率、位深、版本、发布组、音频声道和字幕轨道，并在海报上显示对应标签',
    '支持每天自动检查 GitHub 最新正式版，也可以在“关于”页面手动检查；发现新版本后可打开官方下载页面',
    '修复个人网盘海报往返浏览时重新显示占位图的问题，已经加载的海报会保持显示',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频和字幕',
  ],
);

const VersionHistory _androidEighthRelease = VersionHistory(
  version: '1.0.7',
  date: '2026-08-27',
  changes: [
    '手机和平板增强资源标签识别，新增 Hami Video、Max、TVING、KKTV 等流媒体来源，以及 Hybrid、Proper、Repack、Remastered、Open Matte 等版本标签',
    '本地媒体库、个人网盘、播放历史和 TMDB 匹配等封面统一为 2:3，改善深色模式下原图白边，并统一无海报、加载中和加载失败时的占位显示',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
);

const VersionHistory _androidNinthRelease = VersionHistory(
  version: '1.0.8',
  date: '2026-08-28',
  changes: [
    '手机和平板增强资源标签识别，新增 Hami Video、Max、TVING、KKTV 等流媒体来源，以及 Hybrid、Proper、Repack、Remastered、Open Matte 等版本标签',
    '本地媒体库、个人网盘、播放历史和 TMDB 匹配等封面统一为 2:3，改善深色模式下原图白边，并统一无海报、加载中和加载失败时的占位显示',
    '观看历史支持“继续观看”和“全部历史”切换，按时间分组显示进度、集数和标题，并优化列表布局',
    '修复本地和个人网盘观看历史海报缺失；已有媒体库海报会自动回填并减少重复加载',
    '电影、动漫和电视剧分类页复用媒体库快照，媒体变化或 TMDB 更新时仍会及时同步，减少重复扫描造成的卡顿',
    '修复 Windows 外部播放器把普通播放列表误判为 HLS 的问题',
    '本次更新不会修改、删除、改名或移动本地及个人网盘原始视频、字幕和海报缓存',
  ],
);

const VersionHistory _androidAdaptiveQuarkSystemBarsPrerelease = VersionHistory(
  version: '2.1.103',
  date: '2026-08-03',
  isPrerelease: true,
  changes: [
    'Android 2.1.103 测试版为夸克原画播放新增自适应高速调度：缓存跟不上时最多启用八路读取和七路后台预取，当前播放临时缓存上限为 192 MiB',
    '网络重新连接或播放地址刷新时会自动回到稳健档位，缓存恢复后再按实际压力提速，避免固定高并发造成额外抖动',
    '普通页面的状态栏和底部手势区现在与界面同色，消除底部黑边；播放页系统栏随画面变黑，全屏继续保持彻底沉浸',
    '继续使用官方 Full 原生媒体包，为只有 TrueHD/MLP 音轨的视频提供软件解码和立体声输出；当前测试版待实机验证',
    'Android 百度及迅雷读取策略保持不变',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidImmersiveTrueHdPrerelease = VersionHistory(
  version: '2.1.102',
  date: '2026-08-03',
  isPrerelease: true,
  changes: [
    'Android 2.1.102 测试版改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证',
    'TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路',
    '横屏播放器进入彻底沉浸模式，控制层显示时系统栏仍保持隐藏，边缘滑动可临时唤出',
    '旋转设备、切换后台再返回或窗口重新获得焦点后会恢复沉浸；退出播放器时恢复系统栏和原有方向策略',
    '诊断日志新增 full-v1.1.11 原生媒体包标识，便于确认实际安装的测试组件',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidDiagnosticLogSharePrerelease = VersionHistory(
  version: '2.1.101',
  date: '2026-08-03',
  isPrerelease: true,
  changes: [
    'Android 2.1.101 测试版在错误日志页面新增“导出诊断日志”入口，遇到播放问题时可直接生成完整诊断包',
    '导出完整脱敏诊断包后会打开系统分享面板，可发送到其他应用或保存到文件，无需申请全盘存储权限',
    '诊断包包含应用、系统、解码设置和播放器底层日志，并继续隐藏网盘凭据、Token、请求头与远程媒体完整地址',
    '导出不会清空原日志；日志为空或页面读取失败时仍可尝试取得底层诊断文件',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidAnime4kShaderListRelease = VersionHistory(
  version: '2.1.98',
  date: '2026-08-02',
  isPrerelease: true,
  changes: [
    '修复 Android 启用 Anime4K 时可能把多条着色器路径误当成一个文件名、导致视频无法打开的问题',
    'Anime4K 着色器现在按既定顺序逐个加载；任一着色器失败后会安全清空增强并保留普通播放',
    '关于页当前版本下方新增“更新说明”，可随时查看本版本 Android 更新内容，不影响升级后的首次启动提示',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidCloudHighThroughputRelease = VersionHistory(
  version: '2.1.97',
  date: '2026-08-02',
  isPrerelease: true,
  changes: [
    'Android 夸克与百度网盘的高码率视频读取现在可使用最多六路连接和五路后台预取',
    '连续播放的前向预取窗口扩大到 40 MiB，改善高质量视频加载和卡顿恢复速度',
    '网盘中转缓存仍限制为 128 MiB，不会因提高读取并发继续增加缓存占用',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidLogAnime4kRelease = VersionHistory(
  version: '2.1.96',
  date: '2026-08-01',
  isPrerelease: true,
  changes: [
    '运行记录中的每条日志新增复制按钮，可直接复制该条完整脱敏原文，同时保留复制全部、展开和局部选择',
    'Android 自动渲染器实际使用 GPU 后端时，Anime4K 效率档和质量档现在可正常选择和运行',
    'Anime4K 仍只在画面需要放大时运行；着色器加载失败会安全关闭增强，普通播放不受影响',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _androidNetworkRelease = VersionHistory(
  version: '2.1.95',
  date: '2026-08-01',
  isPrerelease: true,
  changes: [
    'Android 网盘视频连续播放改为三路后台预取，并把前向预取窗口扩大到 24 MiB，改善移动网络高延迟或单连接速度不足时的加载和拖动恢复速度',
    'Android 网盘中转与直连播放器缓存限制为 128 MiB；开启低内存模式后降到 64 MiB，避免沿用桌面端大缓存造成手机和平板内存压力',
    'Android 网盘中转缓存上限调整为 128 MiB，在提高预取并发的同时控制应用缓存目录占用',
    '修复多路分段同时下载时读取速度显示偏低的问题，当前速度会按实际重叠传输时间统计',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);

const VersionHistory _android2199Prerelease = VersionHistory(
  version: '2.1.199',
  date: '2026-08-30',
  isPrerelease: true,
  changes: [
    'Android 2.1.199 测试版汇总近期手机版更新，继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
    '优化夸克网盘低速播放：首次响应较慢时继续等待，读取分块和并发会根据首字节时间、实际吞吐和超时情况动态调整，拖动、切集和重播保留有界重试',
    '观看历史会显示真实集数、进度和海报；新播放不足 10 秒不再产生记录，并修复新进度可能被旧写入覆盖的问题',
    '本地视频改名、移动或新增剧集后，可在身份明确时保留或继承已有 TMDB 资料与手动匹配；无 API Key 或断网时仍可完成离线同步',
    '电影、动漫和电视剧分类页会复用媒体库快照并过滤已删除的本地文件；再次进入网盘资源页会保留已加载的海报墙和媒体状态，减少重复扫描',
    '更新说明弹窗会按内容高度显示，“知道了”按钮可正常关闭；关于页可随时重新查看当前版本内容',
    '播放网盘视频时不再在画面顶部显示常态读取速度；底部控制栏网速、预缓冲和低速或失败提示继续保留',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
);

const VersionHistory _android200Prerelease = VersionHistory(
  version: '2.1.200',
  date: '2026-08-30',
  isPrerelease: true,
  changes: [
    'Android 2.1.200 测试版在手机和平板上默认显示海报紧凑信息，点击海报可打开详情面板查看文件名、评分和技术规格；继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
    '本轮 Android 手机和平板的海报详情交互与媒体播放能力保持可用；Windows 的加载状态、异步确认和播放器失败重试继续保留',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
);

const VersionHistory _android201Prerelease = VersionHistory(
  version: '2.1.201',
  date: '2026-08-30',
  isPrerelease: true,
  changes: [
    'Android 2.1.201 测试版在手机和平板上默认显示与 Windows 一致的完整海报信息浮窗，点击海报直接执行播放主动作；媒体详情仍可从媒体操作菜单进入',
    '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
);

const VersionHistory _androidCurrentPrerelease = VersionHistory(
  version: '2.1.202',
  date: '2026-08-31',
  isPrerelease: true,
  changes: [
    'Android 2.1.202 测试版取消手机和平板海报墙上的常驻信息浮窗；点击网盘资源或分类海报统一进入底部媒体详情/选集界面，在详情中查看简介、技术信息和资源明细后再播放',
    '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
);

const VersionHistory _android203Prerelease = VersionHistory(
  version: '2.1.203',
  date: '2026-08-31',
  isPrerelease: true,
  changes: [
    'Android 2.1.203 测试版修复部分资源在分类详情和网盘选集面板中不显示 4K、来源、编码等技术规格标签的问题；优先使用资源已保存的结构化标签',
    '继续支持本地媒体库、个人网盘、字幕、音轨、后台播放、画中画、MediaCodec 硬件解码和 Anime4K',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
);
