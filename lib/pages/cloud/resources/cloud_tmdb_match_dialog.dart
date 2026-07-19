import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

typedef CloudTmdbSearchCallback = Future<CloudResourceTmdbSearchOutcome>
    Function(CloudResourceTmdbSearchRequest request);
typedef CloudTmdbApplyCallback = Future<CloudResourceTmdbSelectionOutcome>
    Function(TmdbRankedCandidate candidate, TmdbScrapeOptions options);

class CloudTmdbMatchDialog extends StatefulWidget {
  const CloudTmdbMatchDialog({
    super.key,
    required this.title,
    required this.draft,
    required this.initialOptions,
    required this.onSearch,
    required this.onApply,
  });

  final String title;
  final TmdbMatchDraft draft;
  final TmdbScrapeOptions initialOptions;
  final CloudTmdbSearchCallback onSearch;
  final CloudTmdbApplyCallback onApply;

  @override
  State<CloudTmdbMatchDialog> createState() => _CloudTmdbMatchDialogState();
}

class _CloudTmdbMatchDialogState extends State<CloudTmdbMatchDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _yearController;
  late TmdbMediaTypeMode _mediaTypeMode;
  late TmdbScrapeOptions _options;
  CloudResourceTmdbSearchOutcome? _outcome;
  TmdbRankedCandidate? _selected;
  String? _titleError;
  String? _yearError;
  String? _operationError;
  var _searching = false;
  var _saving = false;
  var _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.draft.searchTitle);
    _yearController = TextEditingController(
      text: widget.draft.year?.toString() ?? '',
    );
    _mediaTypeMode = widget.draft.mediaTypeMode;
    _options = widget.initialOptions.copyWith(
      mediaTypeMode: widget.draft.mediaTypeMode,
    );
  }

  @override
  void dispose() {
    _requestGeneration++;
    _titleController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching || _saving) return;
    final query = _titleController.text.trim();
    final yearText = _yearController.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    final invalidYear = yearText.isNotEmpty &&
        (yearText.length != 4 || year == null || year < 1000 || year > 9999);
    if (query.isEmpty || invalidYear) {
      setState(() {
        _titleError = query.isEmpty ? '请输入搜索词' : null;
        _yearError = invalidYear ? '请输入四位年份' : null;
      });
      return;
    }
    final generation = ++_requestGeneration;
    final effectiveOptions = _options.copyWith(mediaTypeMode: _mediaTypeMode);
    setState(() {
      _titleError = null;
      _yearError = null;
      _operationError = null;
      _searching = true;
      _selected = null;
    });
    try {
      final outcome = await widget.onSearch(
        CloudResourceTmdbSearchRequest(
          queryTitle: query,
          queryYear: year,
          mediaTypeMode: _mediaTypeMode,
          options: effectiveOptions,
        ),
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _outcome = outcome);
    } on Object catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _operationError = _errorMessage(error));
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _apply() async {
    final candidate = _selected;
    if (candidate == null || _saving || _searching) return;
    setState(() {
      _saving = true;
      _operationError = null;
    });
    try {
      final outcome = await widget.onApply(
        candidate,
        _options.copyWith(mediaTypeMode: _mediaTypeMode),
      );
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _operationError = _errorMessage(error);
      });
    }
  }

  void _close() {
    if (!_saving) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = math.min(960.0, math.max(280.0, media.width - 64));
    final height = math.min(720.0, math.max(420.0, media.height - 64));
    return Dialog(
      key: const ValueKey<String>('cloud-tmdb-match-dialog'),
      clipBehavior: Clip.antiAlias,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _close,
        },
        child: Focus(
          autofocus: true,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 720) {
                        return SingleChildScrollView(
                          key: const ValueKey<String>('cloud-tmdb-stacked'),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _preparation(context),
                              const SizedBox(height: 20),
                              SizedBox(height: 300, child: _results(context)),
                            ],
                          ),
                        );
                      }
                      return Row(
                        key: const ValueKey<String>('cloud-tmdb-two-column'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 340,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: _preparation(context),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: _results(context),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                _actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  widget.draft.originalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: _saving ? null : _close,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _preparation(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey<String>('cloud-tmdb-search-title'),
          controller: _titleController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: '搜索词',
            errorText: _titleError,
          ),
          onChanged: (_) {
            if (_titleError != null) setState(() => _titleError = null);
          },
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<TmdbMediaTypeMode>(
          key: const ValueKey<String>('cloud-tmdb-media-type'),
          initialValue: _mediaTypeMode,
          decoration: const InputDecoration(labelText: '媒体类型'),
          items: const [
            DropdownMenuItem(
              value: TmdbMediaTypeMode.auto,
              child: Text('自动判断'),
            ),
            DropdownMenuItem(
              value: TmdbMediaTypeMode.movie,
              child: Text('电影'),
            ),
            DropdownMenuItem(
              value: TmdbMediaTypeMode.tv,
              child: Text('电视剧'),
            ),
          ],
          onChanged: _searching || _saving
              ? null
              : (value) {
                  if (value != null) setState(() => _mediaTypeMode = value);
                },
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey<String>('cloud-tmdb-year'),
          controller: _yearController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            labelText: '年份（可选）',
            errorText: _yearError,
            counterText: '',
          ),
          onChanged: (_) {
            if (_yearError != null) setState(() => _yearError = null);
          },
          onSubmitted: (_) => _search(),
        ),
        if (widget.draft.seasonNumber != null ||
            widget.draft.episodeNumber != null) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.draft.seasonNumber case final season?)
                Chip(label: Text('第 $season 季')),
              if (widget.draft.episodeNumber case final episode?)
                Chip(label: Text('第 $episode 集')),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '仅更新看影音中的资料，不会修改网盘文件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text('本次刮削选项'),
          children: [
            _optionSwitch(
              '覆盖已有标题',
              _options.overwriteTitle,
              (value) => _options = _options.copyWith(overwriteTitle: value),
            ),
            _optionSwitch(
              '覆盖已有简介',
              _options.overwriteOverview,
              (value) => _options = _options.copyWith(overwriteOverview: value),
            ),
            _optionSwitch(
              '覆盖已有海报',
              _options.overwritePoster,
              (value) => _options = _options.copyWith(overwritePoster: value),
            ),
            _optionSwitch(
              '获取海报',
              _options.fetchPoster,
              (value) => _options = _options.copyWith(fetchPoster: value),
            ),
            _optionSwitch(
              '获取背景图',
              _options.fetchBackdrop,
              (value) => _options = _options.copyWith(fetchBackdrop: value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _optionSwitch(
    String title,
    bool value,
    void Function(bool value) update,
  ) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged:
          _searching || _saving ? null : (next) => setState(() => update(next)),
    );
  }

  Widget _results(BuildContext context) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_operationError case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }
    final outcome = _outcome;
    if (outcome == null) {
      return const Center(child: Text('确认左侧识别信息后搜索 TMDB 候选'));
    }
    final candidates = outcome.ranked.candidates;
    if (candidates.isEmpty) {
      return const Center(
        child:
            Text('TMDB 没有返回可用候选\n请修改搜索词或媒体类型后重试', textAlign: TextAlign.center),
      );
    }
    return ListView.separated(
      itemCount: candidates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        return _candidateCard(
          context,
          candidate,
          recommended: index == 0 && outcome.ranked.shouldAutoMatch,
        );
      },
    );
  }

  Widget _candidateCard(
    BuildContext context,
    TmdbRankedCandidate candidate, {
    required bool recommended,
  }) {
    final metadata = candidate.metadata;
    final selected = identical(_selected, candidate);
    final colors = Theme.of(context).colorScheme;
    final poster = TmdbMatchSheet.imageUrl(metadata.posterUrl);
    final year =
        metadata.releaseDate != null && metadata.releaseDate!.length >= 4
            ? metadata.releaseDate!.substring(0, 4)
            : '年份未知';
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _saving ? null : () => setState(() => _selected = candidate),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                height: 82,
                child: poster == null
                    ? const Icon(Icons.movie_outlined, size: 36)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            metadata.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (recommended) const Chip(label: Text('推荐')),
                      ],
                    ),
                    if (metadata.originalTitle?.trim().isNotEmpty == true)
                      Text(metadata.originalTitle!),
                    const SizedBox(height: 4),
                    Text(
                      '$year · ${metadata.mediaType == TmdbMediaType.movie ? '电影' : '电视剧'}'
                      '${metadata.rating == null ? '' : ' · ${metadata.rating!.toStringAsFixed(1)} ★'}',
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (candidate.titleMatched) const Text('标题匹配'),
                        if (candidate.yearMatched) const Text('年份匹配'),
                        if (candidate.typeMatched) const Text('类型匹配'),
                      ],
                    ),
                  ],
                ),
              ),
              Radio<TmdbRankedCandidate>(
                value: candidate,
                groupValue: _selected,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _selected = value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
              onPressed: _saving ? null : _close, child: const Text('取消')),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _searching || _saving ? null : _search,
            child: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('搜索 TMDB'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed:
                _selected == null || _searching || _saving ? null : _apply,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('应用匹配'),
          ),
        ],
      ),
    );
  }

  static String _errorMessage(Object error) {
    final text = error.toString();
    if (text.contains('请先在设置中填写 TMDB API Key')) {
      return '请先在设置中填写 TMDB API Key';
    }
    return 'TMDB 请求失败，请检查网络后重试';
  }
}
