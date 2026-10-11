import 'package:flutter/material.dart';
import 'package:kanyingyin/features/player/application/player_chapter.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';

class PlayerTimelineSegmentEditor extends StatefulWidget {
  const PlayerTimelineSegmentEditor(
      {super.key,
      required this.duration,
      required this.position,
      required this.initial,
      required this.onSave,
      this.chapters = const []});
  final Duration duration;
  final Duration Function() position;
  final List<PlayerTimelineSegment> initial;
  final List<PlayerChapter> chapters;
  final Future<void> Function(List<PlayerTimelineSegment>) onSave;
  @override
  State<PlayerTimelineSegmentEditor> createState() =>
      _PlayerTimelineSegmentEditorState();
}

class _PlayerTimelineSegmentEditorState
    extends State<PlayerTimelineSegmentEditor> {
  final _starts = <PlayerSegmentKind, TextEditingController>{};
  final _ends = <PlayerSegmentKind, TextEditingController>{};
  final _enabled = <PlayerSegmentKind>{};
  final _chapterSelection = <PlayerSegmentKind, int>{};
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final kind in PlayerSegmentKind.values) {
      final segment =
          widget.initial.where((segment) => segment.kind == kind).firstOrNull;
      if (segment != null) _enabled.add(kind);
      _starts[kind] = TextEditingController(
          text: formatPlayerTimelineTime(segment?.start ?? Duration.zero));
      _ends[kind] = TextEditingController(
          text: formatPlayerTimelineTime(segment?.end ?? widget.duration));
    }
  }

  @override
  void dispose() {
    for (final controller in [..._starts.values, ..._ends.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final segments = [
        for (final kind in _enabled)
          PlayerTimelineSegment(
              kind: kind,
              start: parsePlayerTimelineTime(_starts[kind]!.text),
              end: parsePlayerTimelineTime(_ends[kind]!.text))
      ];
      validatePlayerTimelineSegments(segments, widget.duration);
      await widget.onSave(segments);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '保存失败，输入已保留；请确认仍在播放同一个视频后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeField(TextEditingController controller, String label) =>
      Row(children: [
        Expanded(
            child: TextField(
                controller: controller,
                enabled: !_saving,
                decoration:
                    InputDecoration(labelText: label, hintText: 'HH:MM:SS'))),
        TextButton(
            onPressed: _saving
                ? null
                : () {
                    controller.text =
                        formatPlayerTimelineTime(widget.position());
                  },
            child: const Text('当前位置')),
      ]);
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('管理片头/片尾区间'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '当前视频时长 ${formatPlayerTimelineTime(widget.duration)}，保存后确认当前视频上的区间。仅显示标记，不自动跳过或切集。'),
                for (final kind in PlayerSegmentKind.values) ...[
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text(kind == PlayerSegmentKind.intro ? '片头' : '片尾'),
                      value: _enabled.contains(kind),
                      onChanged: _saving
                          ? null
                          : (enabled) => setState(() {
                                if (enabled == true) {
                                  _enabled.add(kind);
                                } else {
                                  _enabled.remove(kind);
                                }
                              })),
                  if (_enabled.contains(kind)) ...[
                    _timeField(_starts[kind]!, '起点'),
                    _timeField(_ends[kind]!, '终点'),
                    if (widget.chapters.isNotEmpty)
                      DropdownButton<int>(
                        isExpanded: true,
                        value: _chapterSelection[kind],
                        hint: const Text('使用章节区间'),
                        items: [
                          for (var i = 0; i < widget.chapters.length; i++)
                            DropdownMenuItem(
                                value: i,
                                child: Text(widget.chapters[i].title,
                                    overflow: TextOverflow.ellipsis))
                        ],
                        onChanged: _saving
                            ? null
                            : (index) {
                                if (index == null) return;
                                setState(() {
                                  _chapterSelection[kind] = index;
                                  _starts[kind]!.text =
                                      formatPlayerTimelineTime(
                                          widget.chapters[index].position);
                                  _ends[kind]!.text = formatPlayerTimelineTime(
                                      index + 1 < widget.chapters.length
                                          ? widget.chapters[index + 1].position
                                          : widget.duration);
                                });
                              },
                      ),
                  ],
                ],
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : '保存区间')),
        ],
      );
}
