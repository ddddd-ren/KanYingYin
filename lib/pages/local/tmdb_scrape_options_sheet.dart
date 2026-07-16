import 'package:flutter/material.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class TmdbScrapeOptionsSheet extends StatefulWidget {
  const TmdbScrapeOptionsSheet({super.key, required this.initialOptions});

  final TmdbScrapeOptions initialOptions;

  @override
  State<TmdbScrapeOptionsSheet> createState() => _TmdbScrapeOptionsSheetState();
}

class _TmdbScrapeOptionsSheetState extends State<TmdbScrapeOptionsSheet> {
  late TmdbScrapeOptions _options;

  @override
  void initState() {
    super.initState();
    _options = widget.initialOptions;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本次刮削选项', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            DropdownButtonFormField<TmdbMediaTypeMode>(
              initialValue: _options.mediaTypeMode,
              decoration: const InputDecoration(labelText: '媒体类型'),
              items: const [
                DropdownMenuItem(
                    value: TmdbMediaTypeMode.auto, child: Text('自动判断')),
                DropdownMenuItem(
                    value: TmdbMediaTypeMode.movie, child: Text('电影')),
                DropdownMenuItem(
                    value: TmdbMediaTypeMode.tv, child: Text('电视剧')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(
                      () => _options = _options.copyWith(mediaTypeMode: value));
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('覆盖已有标题'),
              value: _options.overwriteTitle,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(overwriteTitle: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('覆盖已有简介'),
              value: _options.overwriteOverview,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(overwriteOverview: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('覆盖已有海报'),
              value: _options.overwritePoster,
              onChanged: (value) => setState(
                  () => _options = _options.copyWith(overwritePoster: value)),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_options),
                  child: const Text('开始刮削'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
