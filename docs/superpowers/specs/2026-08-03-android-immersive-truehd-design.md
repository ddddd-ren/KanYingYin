# Android 沉浸式全屏与 TrueHD 解码设计

## 背景

Android `2.1.101` 测试版播放用户提供的 4K MKV 时能够识别 TrueHD 音轨，但选择该音轨后无声并切换到兼容音轨。诊断日志包含以下确定性证据：

- 容器正确识别 `truehd 8ch 48000 Hz` 音轨。
- 选择音轨后 FFmpeg 报告 `Codec list: (no decoders)`。
- libmpv 随后报告 `Failed to initialize a decoder for codec 'truehd'`。
- 立体声和降混属性已成功设置，因此问题不在声道配置或 Android 音频输出。

当前 Android 原生库来自 Predidit `libmpv-android-video-build v1.2.5` 的 `default-*.jar`。其 FFmpeg 配置启用了 TrueHD 解封装，却在禁用全部解码器后没有重新启用 TrueHD/MLP 解码器，因此应用能显示音轨信息但不能解码音频。Predidit v1.2.6 仍只发布 Default 资产，不能通过普通依赖升级解决。

用户截图同时显示横屏播放器底部保留白色系统导航区域。现有实现只在进入全屏时调用一次隐藏系统栏；方向变化、窗口焦点变化或恢复前台后，系统可以重新显示导航栏，而应用没有持久保存并恢复沉浸状态。

## 已确认决策

- 安卓全屏使用“彻底沉浸”：控制层显示时系统栏仍保持隐藏，只有边缘滑动才临时唤出。
- TrueHD 使用 FFmpeg 软件解码并下混为立体声 PCM，不做 HDMI 原码直通，也不优先输出多声道 PCM。
- 本轮使用 media-kit 官方 Full v1.1.11 预编译原生库，不安装 WSL，不自编原生库。
- 当前迭代仍是测试版；只有完成实机回归并获得确认后，后续正式版本才允许推送。

## 目标

- Android 能直接播放只有 TrueHD/MLP 音轨的视频并输出稳定的立体声。
- TrueHD 音频软件解码不得关闭或重建现有视频硬件解码链路。
- 横屏播放器不再保留底部白色系统导航区，视频和控制层使用完整可用高度。
- 旋转、窗口重新获得焦点和应用恢复前台后，播放器继续保持沉浸状态。
- 退出全屏或离开播放器后恢复正常系统栏和既有屏幕方向行为。
- Full 原生资产来源、版本和哈希可复现；下载或验证失败时禁止产出安装包。
- Windows 播放器原生依赖和行为保持不变。

## 非目标

- 不实现 TrueHD/Atmos HDMI 原码直通。
- 不保证 5.1 或 7.1 多声道 PCM 输出。
- 不修改视频文件、音轨或网盘源文件。
- 不更换 media-kit 播放器架构，不新增独立音频播放管线。
- 不重排播放器控件，不改变现有动画时长、曲线、快捷操作或画面比例。
- 不在本轮正式推送代码或发布正式版本。

## Android Full 原生依赖

### 依赖边界

在仓库的 `third_party/media_kit_libs_android_video_full` 新增 Android 专用本地依赖适配包，包名保持 `media_kit_libs_android_video`，通过 `dependency_overrides` 的相对路径替换当前传递依赖。适配包复用当前固定 media-kit 提交中的 Android Manifest、插件入口和 Java helper，只替换 Gradle 下载的原生 JAR 资产。

适配包不得修改 Pub 缓存，也不得影响 Windows、macOS、Linux 或 iOS 的依赖选择。删除该 override 后应能恢复当前 Default 原生包，便于独立回滚。

### 固定资产

来源固定为 media-kit 官方 `libmpv-android-video-build v1.1.11` Full 资产：

| ABI | 文件 | SHA-256 |
| --- | --- | --- |
| arm64-v8a | `full-arm64-v8a.jar` | `cdb54c5cf24725623ca717bbbd6d991031d625a377460bd128f19c2dffe189bd` |
| armeabi-v7a | `full-armeabi-v7a.jar` | `b658f2ff91169f8dad0e09e0240ebe200bb3df999da5712f8fab96ad11a4fbec` |
| x86 | `full-x86.jar` | `8b3b84e54ec09bb79972095dc04bcaf651294da4e73b1e7c3251055fd8a2b901` |
| x86_64 | `full-x86_64.jar` | `848936cfd7333077f21759adaca4a9e1a5647891da2e42ab211c5bdc30f4535d` |

Gradle 下载任务对每个文件执行 SHA-256 校验。缓存文件哈希不符时先删除再重新下载；重新下载仍不匹配、网络失败或任一 ABI 缺失时构建立即失败。禁止退回 Default 包，也禁止继续使用未验证缓存。

### 播放数据流

1. media-kit 继续使用当前 libmpv FFI、视频表面和 MediaCodec 视频硬解路径。
2. 打开 MKV 后，libmpv 从 Full FFmpeg 中选择 `truehd` 或 `mlp` 软件音频解码器。
3. 播放器在选择 TrueHD/MLP 音轨前继续设置 `audio-channels=stereo` 和 `ad-lavc-downmix=yes`。
4. 解码后的 PCM 通过 Android OpenSL ES 以立体声输出。
5. 视频仍按用户设置使用 MediaCodec 硬解；TrueHD 不触发 `hwdec=no` 或视频重载。

诊断摘要新增 Android 原生媒体包标识 `full-v1.1.11`，便于区分用户是否实际运行本次测试包。

## TrueHD 错误处理

现有兼容音轨回退继续作为防御措施，但不参与正常 TrueHD 播放：

- Full 解码器正常时，只有 TrueHD 音轨的视频直接有声，不进入回退分支。
- TrueHD 仍失败且存在非 TrueHD 音轨时，允许切换到现有兼容音轨并提示用户。
- TrueHD 仍失败且没有兼容音轨时，保持视频播放，显示“当前播放器组件无法解码此音轨，请导出诊断日志”，不反复重建播放器。
- 所有错误日志继续经过现有脱敏和诊断 ZIP 导出链路。

运行时成功判据是日志同时出现 TrueHD 解码器选择、OpenSL ES 立体声输出和音频进入播放状态，并且没有出现 `(no decoders)`、TrueHD 初始化失败或兼容音轨自动切换。

## 持久沉浸式全屏

### 原生控制器

将 MainActivity 中一次性的 `handleSetImmersive` 行为收敛为 Android 原生沉浸控制器。控制器保存 `immersiveRequested` 状态，并提供进入、退出和按需重新应用三个操作。

Android 11 及以上使用 `WindowInsetsController`：

- 设置 `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`。
- 进入时隐藏状态栏和导航栏。
- 调用 `window.setDecorFitsSystemWindows(false)` 让内容绘制到系统栏区域，并将系统栏颜色设为透明。
- Android 10 及以上关闭导航栏对比度强制，避免系统生成白色或不透明导航背景。

Android 10 及以下继续使用现有 `IMMERSIVE_STICKY`、`FULLSCREEN`、`HIDE_NAVIGATION` 和布局标志，保持最低版本兼容。

退出沉浸时显示系统栏，恢复进入前保存的系统栏颜色、对比度行为和正常内容区域。

### 生命周期恢复

只要 `immersiveRequested` 为真，在以下边界重新应用沉浸状态：

- Activity 恢复前台。
- 窗口重新获得焦点。
- 横竖屏或屏幕尺寸配置发生变化。

重复应用必须幂等，不创建计时器，不持续轮询，也不在沉浸状态已退出后再次隐藏系统栏。

Flutter `WindowUtils` 继续负责现有横屏方向策略和 MethodChannel 调用。播放器控件层级、SafeArea 横向避让、返回键策略、自动隐藏计时和动画保持不变；全屏底部不再为白色导航栏预留高度。

## 测试设计

### 自动化测试

- 原生依赖契约测试验证本地 override 生效、四个 URL 和 SHA-256 完整、只引用 `full-*.jar`，且不存在 `default-*.jar` 下载项。
- Android 播放兼容测试验证 TrueHD 仍设置立体声和降混，且不触发软件视频解码重建。
- 沉浸模式契约测试验证持久状态、透明导航栏、关闭对比度、滑动临时系统栏以及恢复前台、焦点和配置变化时重新应用。
- 现有播放器返回、字幕、选轨、硬解、日志与诊断导出测试全部保留。
- `flutter test` 全量通过，`flutter analyze` 无错误。

### 包级验证

- Android Release APK 和 AAB 构建成功。
- APK v2 签名有效，AAB 严格 JAR 签名有效。
- 包身份为 `com.kanyingyin.player`，版本名、版本码和测试版标识一致。
- APK 中四个 ABI 的 `libmpv.so` 与对应 Full JAR 内容一致，不混入 Default `libmpv.so`。
- 桌面 APK/AAB 与构建目录产物哈希一致。

### Android 实机验收

使用用户本次问题文件完成以下验证：

- 选择唯一或默认 TrueHD 音轨后持续有声，声道平衡正常。
- 日志出现 `Selected decoder: truehd`、OpenSL ES 立体声输出和 `audio=playing`。
- 不出现 `Codec list: (no decoders)`、TrueHD 初始化失败或自动切换兼容音轨。
- 4K HEVC 视频仍使用 MediaCodec 硬解，播放、暂停、拖动和缓冲恢复正常。
- AC3、DTS、普通立体声音轨和内嵌字幕可以选择并正常播放。
- 夸克等现有网盘代理播放、跳播和退出流程无回归。
- 进入横屏后底部白色导航区消失。
- 显示控制层、旋转设备、切换后台再返回后仍保持沉浸。
- 从屏幕边缘滑动可以临时唤出系统栏；退出播放器后系统栏和方向恢复。

在收到新的实机诊断日志前，发布文案只能描述为“测试修复，待实机验证”，不能宣称 TrueHD 已正式修复。

## 版本与交付

实施开始前按项目规则查询 `Get-AppxPackage -Name com.kanyingyin.player` 并记录当前 Windows 安装版本。若源码和已安装版本仍为 `2.1.101`，本轮使用测试版 `2.1.102`；若期间已有更高版本，则选择严格高于两者的下一个版本。

版本号、Android 版本码、MSIX 版本、`RELEASE_NOTES.md` 和 `lib/utils/version_history.dart` 同步更新，测试版标识保持开启。完成全量测试、静态分析和 Windows/Android Release 后，生成并验证签名 MSIX、APK 和 AAB，复制到当前用户桌面。不得自动推送或发布正式版本。

## 风险与回滚

- Full v1.1.11 早于当前 Predidit v1.2.5 原生基线，可能影响 HEVC、HLS、字幕或部分设备兼容性，因此必须以实机回归作为采用条件。
- TrueHD 软件解码会增加 CPU 和耗电，但立体声降混比多声道输出更可控；视频硬解保持开启以限制总负载。
- 不同 Android 厂商可能在焦点或手势操作后重新显示系统栏，持久沉浸恢复点用于覆盖这些差异。
- Full 依赖和沉浸控制器分开提交。若 Full 库产生回归，只回滚本地 Android 原生依赖 override；若沉浸模式产生系统栏恢复问题，只回滚原生沉浸控制器。
- 任一关键回归、签名失败、资产哈希不一致或实机仍无 TrueHD 声音时，停止正式交付并保留诊断日志，不以兼容音轨回退冒充修复成功。
