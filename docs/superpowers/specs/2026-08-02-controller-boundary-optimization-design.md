# 看影音控制器边界完整优化设计

## 背景

看影音已经完成应用绑定拆分、强类型设置、本地与网盘协调器、播放器策略、表现组件、legacy 隔离和索引缓存等渐进式优化。当前主要维护风险不再是目录缺失，而是三个 UI 控制器仍同时承担状态、事务编排和基础设施副作用：

- `LocalController` 约 1636 行，负责目录导航、媒体来源、索引事务、本地与网盘目录视图、元数据和 TMDB 门面。
- `CloudResourcesController` 约 1161 行，负责来源快照、扫描、隐藏记录、目录范围、TMDB 和自动整理。
- `PlayerController` 约 2005 行，负责 media-kit 生命周期、播放资源、字幕音轨、云链接恢复、Anime4K 和 UI 状态。

本设计完成这三个边界的连续优化，不以减少行数为唯一目标，也不进行状态管理框架迁移或一次性目录搬迁。

## 目标与成功标准

1. 保留 Flutter Modular、MobX、ChangeNotifier、现有路由以及控制器供页面使用的公开 API。
2. 页面仍只通过控制器读取状态和触发动作；控制器不再直接编排多仓储事务或创建底层服务。
3. 本地与网盘控制器不得构造 Repository/具体 Service，也不得直接编排跨多个仓储的事务；稳定数据类型和单一策略接口可以保留，底层实现由应用协调器和强类型端口承接。
4. `PlayerController` 不再通过 `Modular.get` 解析依赖；media-kit 创建、打开、刷新和释放由专用运行时边界负责。
5. 保持目录导航、扫描取消、过期结果丢弃、TMDB 离线降级、播放器生命周期、字幕、音轨、硬件解码和 Anime4K 行为不变。
6. 删除来源、索引或缓存仍不得删除用户本地或远端原始媒体。
7. 每个新边界具备独立单元测试，并由架构测试阻止职责回流。
8. 全量测试、静态分析、Windows Release、Android Release 和交付包验证全部通过后才视为完成。

## 方案比较

### 方案 A：保留门面的分阶段提取（采用）

控制器保留可观察状态和兼容 API，把稳定事务移入构造注入的协调器。每一阶段先用现有行为建立特征测试，再提取一条完整链路并执行全量回归。

优点是回归面可控、页面无需同步重写、可以复用现有测试；缺点是过渡期内控制器仍保留部分映射代码。

### 方案 B：重写控制器 API 和页面调用

按新功能切片同时修改控制器、路由参数和页面。最终接口可能更简洁，但会把架构调整与 UI、导航、播放器生命周期回归混在一起，问题难以归因。

### 方案 C：迁移状态管理和依赖注入框架

用 Riverpod、BLoC 或其他框架替换 MobX、ChangeNotifier 和 Flutter Modular。迁移成本最大，而且不能自动解决扫描、播放和仓储事务的职责混杂，本轮不采用。

## 总体架构

统一调用方向：

```text
Widget / Route
    -> Controller facade（可观察状态、公开 API、状态提交）
    -> Application coordinator（事务、取消、代际、强类型结果）
    -> Repository / Service port（持久化、扫描、网络、播放器）
    -> Result / Progress event
    -> Controller facade（确认仍为当前操作后提交）
```

约束如下：

- Controller 不创建 Repository、网络客户端、扫描器或插件实例。
- Coordinator 不依赖 Widget、BuildContext、Flutter Modular 或具体页面。
- Repository/Service 不直接修改控制器状态。
- 进度通过强类型事件回调传递，完成结果使用不可变对象返回。
- 仅应用绑定层决定实例生命周期，继续保持当前应用级单例语义。
- 本地和网盘协调器放在对应的 `features/*/application` 目录；播放器端口放在 `features/player/application`，media-kit 实现放在 `features/player/infrastructure`。
- 新结果与进度类型先与其协调器放在同一文件，只有被两个以上边界复用时再移动到独立文件，避免为目录整齐制造碎片。

## 阶段一：本地媒体库边界

### LocalDirectoryNavigationCoordinator

负责目录初始化、导航、刷新、排序、向上导航、最近目录记录、媒体来源扫描摘要和过期导航结果识别。输入包含目标位置和排序规则，输出不可变的目录快照；不持有 MobX 状态。

`LocalController` 继续持有 `currentPath`、`items`、`isLoading`、`errorMessage`、`sortBy`、`sortAscending` 和 `pathHistory`，并决定何时把快照提交给 UI。

### LocalLibraryIndexCoordinator

负责遍历可用来源、选择文件系统或 Android 文档索引入口、取消检查、进度聚合、来源可访问状态、扫描摘要更新和严格模式异常传播。返回包含数量、失败项、取消状态和来源可访问性的结果。

控制器继续暴露现有扫描状态字段和 `refreshLocalLibraryIndex`、`cancelLocalLibraryIndex` 兼容方法，但不再直接操作索引器和来源仓储。

### LocalLibraryCatalogCoordinator

负责读取本地与网盘索引、按当前来源配置过滤失效缓存、刷新指定网盘来源、生成合并媒体库输入和重新加载目录。现有 `LocalMediaLibraryBuilder` 继续负责纯分组与视图模型构建。

本阶段不重复拆分已经存在的来源、元数据和 TMDB 协调器；它们由新协调器组合或继续直接注入。

## 阶段二：网盘资源边界

### CloudResourceSnapshotCoordinator

负责加载来源、选择来源、读取已索引快照、按根目录过滤旧缓存、维护操作 generation，并在来源切换时拒绝提交过期结果。控制器只提交 `sources`、`selectedSource`、`entries` 和错误状态。

### CloudResourceScanCoordinator

负责启动、取消和等待来源扫描，聚合目录进度，保证失败或 dispose 时清理扫描状态，并把扫描结果交给快照协调器重新加载。它复用现有 `CloudMediaIndexer`，不改变同一来源不可并发扫描的契约。

### CloudHiddenVideoCoordinator

负责隐藏、恢复和全部恢复的持久化事务。只有仓储写入成功才返回新的隐藏记录快照；写入失败时控制器保留原状态。

现有 TMDB 门面、自动整理器、目录范围树和集合分组器继续作为独立组件，不重复包装。

## 阶段三：播放器边界

### PlayerEngineRuntime

定义播放器创建、媒体打开、暂停、恢复、跳转、音量、速度、截图、停止和资源释放的运行时边界。media-kit 的 `Player`、`VideoController`、订阅和 NativePlayer 配置由实现类集中持有。

界面仍通过 `PlayerController` 获取可渲染的视频控制器和 MobX 状态；运行时通过强类型快照和事件把播放、缓冲、位置、时长及错误回传。

作为 Flutter 表现层桥接，`PlayerController` 可以继续暴露 `VideoController?`；`Player`、`NativePlayer`、插件订阅和原生属性设置必须留在 media-kit 运行时实现内部。

### PlayerMediaSessionCoordinator

负责播放器生命周期 token、媒体操作 token、初始化锁、云播放 lease、过期链接刷新事务和重新打开后的播放状态恢复。过期操作必须关闭自己的 lease，不能覆盖当前媒体。

### PlayerTrackRuntimeCoordinator

负责把已有字幕、内嵌音轨和语言策略应用到当前 NativePlayer。现有 `PlayerSubtitleCoordinator`、`EmbeddedTrackCoordinator` 和偏好组件继续负责纯规则与持久化；新协调器只承接插件副作用。

`LocalVideoController` 改为构造注入播放器生命周期端口，不再使用 `Modular.get<PlayerController>()`，但仍保持“先写入播放会话，再进入 `/video/`”的现有路由契约。

## 错误、取消与生命周期

- 非严格的目录和索引操作继续把错误映射为现有中文状态；严格调用继续抛出明确异常。
- 每个异步事务拥有 generation 或 token，只有当前操作可以提交状态。
- 取消发生在保存前时不提交部分索引；保存完成后的结果遵循现有仓储原子性。
- Coordinator 在 `finally` 中清理 busy 状态；Controller 在 dispose 后不通知监听器。
- TMDB 无 Key、断网或失败不得阻止本地扫描与播放。
- 播放初始化、刷新和销毁必须串行；旧媒体的事件、订阅和 lease 不得进入新媒体状态。
- 任何失败路径都不得删除用户原始媒体。

## 测试策略

1. 在移动逻辑前补齐公开行为的特征测试，先证明测试可以捕获错误实现。
2. 为每个 Coordinator 建立纯单元测试，覆盖成功、失败、取消、并发和过期结果。
3. 扩展 `architecture_dependency_test.dart`：
   - 本地和网盘 Controller 禁止构造 Repository/具体 Service，禁止保留已提取事务的底层实现字段。
   - Controller 禁止使用 `Modular.get`。
   - Application Coordinator 禁止依赖页面和 Flutter Modular。
   - Player 的 media-kit 创建与释放只能出现在运行时实现。
4. 每个阶段执行相关控制器、页面、平台和播放器回归测试。
5. 所有阶段结束后执行格式检查、完整 `flutter test` 和 `flutter analyze`。
6. 分别构建 Windows Release 与 Android Release；播放器还需实机复核全屏、字幕、选集、硬件解码、Anime4K、后台播放和画中画。

## 交付顺序

1. 本地媒体库：导航协调器 -> 索引协调器 -> 合并目录协调器 -> 架构门禁。
2. 网盘资源：快照协调器 -> 扫描协调器 -> 隐藏记录协调器 -> 架构门禁。
3. 播放器：运行时端口与 media-kit 实现 -> 媒体会话协调器 -> 音轨运行时协调器 -> 移除服务定位。
4. 统一清理失效导入、废弃包装和只为旧内部结构存在的测试假设。
5. 同步版本、README 项目结构、发布说明和版本历史。
6. 完整验证、签名交付、桌面产物核验和 Git 提交。

## 非目标

- 不改变页面布局、控件层级、动画时长、动画曲线、快捷键、手势或导航路径。
- 不替换 Flutter Modular、MobX、ChangeNotifier、Hive CE 或 media-kit。
- 不改变媒体识别、TMDB 匹配、字幕、音轨、硬件解码、Anime4K 和缓存策略。
- 不删除、移动或重命名用户本地及远端原始媒体。
- 不把性能优化与本轮结构调整混合；只有现有性能指标出现回退时才处理回归。
