import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/modules/media/media_custom_tags.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';

Future<bool?> showMediaClassificationDialog(
  BuildContext context, {
  required MediaLibrarySeries series,
  required MediaLibraryUserState state,
  required MediaClassificationMode mode,
  required Future<void> Function(MediaLibraryUserState, List<String>) onSave,
  List<String> customTags = const [],
  bool allowCustomTags = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MediaClassificationDialog(
      series: series,
      state: state,
      mode: mode,
      onSave: onSave,
      customTags: customTags,
      allowCustomTags: allowCustomTags,
    ),
  );
}

class _MediaClassificationDialog extends StatefulWidget {
  const _MediaClassificationDialog({
    required this.series,
    required this.state,
    required this.mode,
    required this.onSave,
    required this.customTags,
    required this.allowCustomTags,
  });

  final MediaLibrarySeries series;
  final MediaLibraryUserState state;
  final MediaClassificationMode mode;
  final Future<void> Function(MediaLibraryUserState, List<String>) onSave;
  final List<String> customTags;
  final bool allowCustomTags;

  @override
  State<_MediaClassificationDialog> createState() =>
      _MediaClassificationDialogState();
}

class _MediaClassificationDialogState
    extends State<_MediaClassificationDialog> {
  late final MediaClassificationResult _automatic =
      const MediaClassificationResolver()
          .resolve(widget.series, mode: widget.mode);
  late List<String>? _categoryOverride =
      widget.state.categoryOverride?.toList();
  late List<String>? _genreOverride = widget.state.genreOverride?.toList();
  late final List<String> _tags =
      MediaCustomTags.normalize(widget.customTags).toList();
  final _tagInput = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _tagError;

  List<String> get _categories => _categoryOverride ?? _automatic.categories;
  List<String> get _genres => _genreOverride ?? _automatic.genres;

  @override
  void dispose() {
    _tagInput.dispose();
    super.dispose();
  }

  void _selectCategory(String label, bool selected) {
    final next = _categories.toList()..remove(label);
    if (selected) {
      if (label == '动漫') next.remove('电视剧');
      if (label == '电视剧') next.remove('动漫');
      next.add(label);
    }
    setState(() => _categoryOverride = next);
  }

  void _selectGenre(String label, bool selected) {
    final next = _genres.toList()..remove(label);
    if (selected) next.add(label);
    setState(() => _genreOverride = next);
  }

  bool _addTag() {
    final value = _tagInput.text.trim();
    if (value.isEmpty) return true;
    if (value.length > MediaCustomTags.maxTagLength) {
      setState(() => _tagError = '标签不能超过 32 个字符');
      return false;
    }
    if (!_tags.any((tag) => tag.toLowerCase() == value.toLowerCase())) {
      if (_tags.length >= MediaCustomTags.maxTags) {
        setState(() => _tagError = '每部作品最多添加 30 个自定义标签');
        return false;
      }
      _tags.add(value);
    }
    setState(() {
      _tagError = null;
      _tagInput.clear();
    });
    return true;
  }

  Future<void> _save() async {
    if (_saving || (widget.allowCustomTags && !_addTag())) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        widget.state.copyWith(
          categoryOverride: _categoryOverride,
          genreOverride: _genreOverride,
          clearCategoryOverride: _categoryOverride == null,
          clearGenreOverride: _genreOverride == null,
          updatedAt: DateTime.now(),
        ),
        List<String>.unmodifiable(_tags),
      );
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '分类与标签保存失败，已保留选择，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final genreLabels = <String>{
      ..._automatic.genreSuggestions.map((value) => value.label),
      ...?_genreOverride,
    };
    return PopScope<bool>(
      canPop: !_saving,
      child: GlassDialog(
        key: const ValueKey('media-classification-dialog'),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('编辑分类与标签', style: textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(widget.series.title,
                    style: textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text(widget.series.sourceName,
                    style: textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('分类门槛：${widget.mode.label}'),
                        Text(mediaClassificationModeDescription(widget.mode),
                            style: textTheme.bodySmall),
                        const SizedBox(height: 12),
                        _sectionTitle('主分类', _categoryOverride, '清空分类',
                            () => setState(() => _categoryOverride = [])),
                        const Text('动漫和电视剧不可同时选择；电影可与动漫同时选择。'),
                        for (final label in const ['电影', '动漫', '电视剧'])
                          _choice(
                            key: ValueKey('classification-category-$label'),
                            label: label,
                            selected: _categories.contains(label),
                            suggestions: _automatic.categorySuggestions,
                            onChanged: (value) => _selectCategory(label, value),
                          ),
                        const SizedBox(height: 12),
                        _sectionTitle('题材标签', _genreOverride, '清空题材',
                            () => setState(() => _genreOverride = [])),
                        const Text('题材标签默认跟随 TMDB；只有主动编辑后才会保存人工覆盖。'),
                        if (genreLabels.isEmpty) const Text('暂无题材建议，可保留空选择。'),
                        for (final label in genreLabels)
                          _choice(
                            key: ValueKey('classification-genre-$label'),
                            label: label,
                            selected: _genres.contains(label),
                            suggestions: _automatic.genreSuggestions,
                            onChanged: (value) => _selectGenre(label, value),
                          ),
                        const SizedBox(height: 12),
                        const Text('高可信：资料匹配且主分类、题材一致。\n'
                            '中可信：已有记录，但完整匹配依据不足。\n'
                            '低可信：信息缺失、冲突或只有季集线索。\n'
                            '可信程度只影响主分类自动归类，不是准确率。'),
                        if (widget.allowCustomTags) ...[
                          const SizedBox(height: 16),
                          Text('自定义标签', style: textTheme.titleSmall),
                          const Text('仅用于整理，不会改变作品的主分类。'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in _tags)
                                InputChip(
                                  label: Text(tag),
                                  onDeleted: _saving
                                      ? null
                                      : () => setState(() => _tags.remove(tag)),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey(
                                      'classification-custom-tag-input'),
                                  controller: _tagInput,
                                  enabled: !_saving,
                                  maxLength:
                                      MediaCustomTags.maxTagLength,
                                  decoration: InputDecoration(
                                    labelText: '新增自定义标签',
                                    errorText: _tagError,
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => _addTag(),
                                ),
                              ),
                              IconButton(
                                tooltip: '添加自定义标签',
                                onPressed: _saving ? null : _addTag,
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 12),
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 4,
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _categoryOverride = null;
                                _genreOverride = null;
                              }),
                      child: const Text('恢复自动'),
                    ),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      key: const ValueKey('classification-save'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title,
    List<String>? selection,
    String clearLabel,
    VoidCallback onClear,
  ) =>
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(selection == null
              ? '自动'
              : selection.isEmpty
                  ? '已清空'
                  : '手动选择'),
          TextButton(
              onPressed: _saving ? null : onClear, child: Text(clearLabel)),
        ],
      );

  Widget _choice({
    required Key key,
    required String label,
    required bool selected,
    required List<MediaClassificationSuggestion> suggestions,
    required ValueChanged<bool> onChanged,
  }) {
    final suggestion =
        suggestions.where((item) => item.label == label).firstOrNull;
    return CheckboxListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(label),
      subtitle: Text(suggestion == null
          ? '手动选择'
          : '${suggestion.confidence.label} · ${suggestion.reason}'),
      value: selected,
      onChanged: _saving ? null : (value) => onChanged(value == true),
    );
  }
}

String mediaClassificationModeDescription(MediaClassificationMode mode) =>
    switch (mode) {
      MediaClassificationMode.conservative =>
        '仅高可信的单一主分类自动归类，多候选仍需选择；题材标签始终跟随 TMDB。',
      MediaClassificationMode.standard =>
        '允许中可信的单一主分类自动归类，多候选仍需选择；题材标签始终跟随 TMDB。',
      MediaClassificationMode.manual => '只给出主分类建议，题材标签始终跟随 TMDB。',
    };

Future<void> showMediaClassificationReviewDialog(
  BuildContext context, {
  required List<MediaLibrarySeries> series,
  required String sourceLabel,
  required Map<String, MediaLibraryUserState> Function() userStatesProvider,
  required MediaClassificationMode Function() modeProvider,
  Future<void> Function(MediaLibrarySeries)? onEdit,
  Future<void> Function(MediaLibrarySeries)? onOpen,
}) async {
  final scrollState = PageStorageBucket();
  while (context.mounted) {
    ModalRoute<Future<void> Function()>? reviewRoute;
    final action = await showDialog<Future<void> Function()>(
      context: context,
      builder: (context) {
        reviewRoute = ModalRoute.of(context);
        void select(Future<void> Function() action) {
          if (reviewRoute?.isCurrent != true) return;
          Navigator.of(context).pop(action);
        }

        return PageStorage(
          bucket: scrollState,
          child: GlassDialog(
            key: const ValueKey('media-classification-review'),
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: MediaQuery.sizeOf(context).height * 0.8,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('检查分类',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                        '预览“$sourceLabel”全部 ${series.length} 部作品；编辑并保存后才会改变分类。'),
                    const SizedBox(height: 12),
                    Flexible(
                      child: series.isEmpty
                          ? const Text('当前来源没有作品。')
                          : ListView.separated(
                              key: const PageStorageKey(
                                  'classification-review-list'),
                              shrinkWrap: true,
                              itemCount: series.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final item = series[index];
                                final result =
                                    const MediaClassificationResolver().resolve(
                                  item,
                                  state: userStatesProvider()[item.key],
                                  mode: modeProvider(),
                                );
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item.title),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.sourceName),
                                      Text(
                                          '有效分类：${result.categories.isEmpty ? '未分类' : result.categories.join(' · ')}'),
                                      Text(
                                          '题材：${result.genres.isEmpty ? '未选择' : result.genres.join(' · ')}'),
                                      Text(result.needsConfirmation
                                          ? '待确认'
                                          : result.isManual
                                              ? '已手动确认'
                                              : '已自动归类'),
                                      for (final suggestion in [
                                        ...result.categorySuggestions,
                                        ...result.genreSuggestions,
                                      ])
                                        Text(
                                            '${suggestion.label} · ${suggestion.confidence.label}：${suggestion.reason}'),
                                      if (result.categorySuggestions.isEmpty)
                                        const Text('信息不足，暂无分类建议；仍可浏览和播放。'),
                                    ],
                                  ),
                                  onTap: onOpen == null
                                      ? null
                                      : () => select(() => onOpen(item)),
                                  trailing: onEdit == null
                                      ? null
                                      : IconButton(
                                          tooltip: '编辑分类与标签',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () =>
                                              select(() => onEdit(item)),
                                        ),
                                );
                              },
                            ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    // 等退出动画移除原弹层后，再开始下一步任务。
    await reviewRoute?.completed;
    if (action == null || !context.mounted) return;
    await action();
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
  }
}
