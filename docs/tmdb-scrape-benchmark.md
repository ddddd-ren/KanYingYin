# TMDB 刮削对标基线

## 运行环境

- 日期：2026-08-05
- 仓库提交：b6f31fe（基线测试前）
- Flutter 测试：`D:/flutter/bin/flutter.bat test --no-pub`
- 全量测试结果：1606 项通过
- 样本测试：`test/tmdb_scrape_benchmark_test.dart`
- 样本数量：30
- 样本候选：本地固定假数据，不访问 TMDB，不包含密钥或个人媒体路径

## 看影音当前基线

| 指标 | 结果 |
| --- | ---: |
| Top-1 正确 | 27/30（90.0%） |
| Top-3 召回 | 27/30（90.0%） |
| 自动确认次数 | 15 |
| 自动确认正确 | 15/15（100%） |
| 典型未命中 | 中文别名、日文罗马字、发布组方括号、纯数字集号、中文纪录片标题 |

当前策略的优点是自动确认保守，缺点是候选召回不足；后续改动必须先保持自动确认精确率，再提高 Top-3 召回。

## 网易爆米花采样

先执行 `doctor`：

- status：`ready`
- version：`0.25.9.0`
- service_port：`52020`

对脱敏关键词“流浪地球2”执行搜索：

```json
{
  "success": true,
  "data": {
    "count": 0,
    "has_more": false,
    "total_count": 0,
    "items": []
  }
}
```

当前爆米花没有返回可对比媒体条目，因此本轮只记录接口状态，不把空结果解释为刮削能力结论。后续配置可用媒体源后，使用相同样本逐条记录标题、年份、媒体类型、排序位置和公开 TMDB ID；不记录 source media_id、凭据或本地协议细节。

## 验收记录

每次候选算法变更后重新运行：

```powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_scrape_benchmark_test.dart -r expanded
```

只有自动确认精确率不低于 98%、Top-3 召回不低于 95%，并且相对本基线自动召回率提升至少 15 个百分点时，才进入发布验收。
