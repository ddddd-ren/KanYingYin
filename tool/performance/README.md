# 媒体库固定样本性能基准

在仓库根目录运行（不进入默认 `flutter test` 全量扫描）：

```powershell
& D:\flutter\bin\flutter.bat test --no-pub tool/performance/library_performance_benchmark_test.dart --dart-define=benchmark_label=after --dart-define=benchmark_repetitions=5 --reporter expanded
```

报告：`build/three_round_validation/performance-after.json`。标签仅使用文件名安全字符。调试可将重复次数改为 1，正式比较使用 5 次。每种规模先预热一次，报告保留所有样本及中位数；先运行改前版本，再以相同脚本、机器及 Flutter 版本运行改后版本。比较前确认两份报告的 `fixtureSha256` 相等，不在构建或其他测试并行执行时采样。

固定 1000/10000 个本地电影，每部一集，包含来源标题、TMDB 中文名、原名及别名，不访问用户媒体或网络。Hive 使用每轮独立系统临时目录，测试结束关闭并删除；不会打开用户设置库。

- `hiveReopenMs`：写好并关闭临时 Hive 后重开；没有清除操作系统文件缓存。
- `indexColdReadMs` / `indexCachedReadMs`：已打开 Hive 上仓库第一次解码和缓存读取。
- `searchMeanMs`：显示名关键词连续 20 次查询的平均时间；`originalTitleSearchMs` 与命中数记录原名查询，改前版本可能为零，不能用速度掩盖功能缺失。
- `bulkWriteFlushMs`：所有条目的一次批量更新及 Hive `flush`，不包含建库和测试数据准备。
- `firstContentWidgetPumpMs`：生产分类页初始化到第一内容帧的 widget pump，断言实际产生可见卡片；不是 GPU 帧耗时，也不是磁盘冷启动。
- RSS：整个 Flutter 测试进程，包含框架/JIT，未强制 GC；差值可以为负。两个规模顺序执行，不能当成单独进程或应用净内存。

这些结果属于 `flutter test` JIT，不能推断实机 Release 首屏。实机 Release 的启动、滚动与内存需另测另报。基准仅测量，不设置跨机器时间阈值。
