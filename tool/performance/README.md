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

## 分类页业务耗时

下列基准用独立进程分别测量两个规模，经过正式的分类控制器与文件存在性检查。每档首次进入一次，再重复进入五次。生成的普通文件位于构建目录，测试使用独立的临时设置库。

```powershell
foreach ($count in 1000, 10000) {
  & D:\flutter\bin\flutter.bat test --no-pub tool/performance/category_switch_benchmark_test.dart --dart-define=benchmark_label=before "--dart-define=benchmark_count=$count" --reporter expanded
  if ($LASTEXITCODE -ne 0) { throw "分类基准失败，样本数 $count" }
}
```

改后使用标签 `after`。两组原始记录位于 `build/navigation_validation/category-标签-数量.json`，对比前核对样本摘要和可见作品数。`readyMs` 统计分类初始化并取得完整作品列表的时间，`nextEventMs` 记录调用后 UI isolate 恢复处理下一个事件的时间。屏幕点击响应和真实出画另用 Windows 应用测量。
