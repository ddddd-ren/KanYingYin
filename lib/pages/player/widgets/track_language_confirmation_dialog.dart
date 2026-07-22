import 'package:flutter/material.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';

class TrackLanguageConfirmationDialog extends StatefulWidget {
  const TrackLanguageConfirmationDialog({
    super.key,
    required this.tracks,
    required this.onConfirm,
  });

  final List<PendingTrackLanguage> tracks;
  final Future<String?> Function(Map<String, TrackLanguageChoice> choices)
      onConfirm;

  @override
  State<TrackLanguageConfirmationDialog> createState() =>
      _TrackLanguageConfirmationDialogState();
}

class _TrackLanguageConfirmationDialogState
    extends State<TrackLanguageConfirmationDialog> {
  final Map<String, TrackLanguageChoice> _choices =
      <String, TrackLanguageChoice>{};
  bool _saving = false;
  String? _error;

  bool get _complete => _choices.length == widget.tracks.length;

  TrackLanguageChoice? _choiceFromText(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    for (final choice in commonTrackLanguageChoices) {
      if (choice.label == text || choice.code == text) {
        return choice.confirmedByUser();
      }
    }
    return TrackLanguageChoice(
      code: 'custom:${Uri.encodeComponent(text)}',
      label: text,
      kind: TrackLanguageKind.other,
      source: TrackLanguageSource.user,
    );
  }

  void _setChoice(String fingerprint, TrackLanguageChoice choice) {
    setState(() {
      _choices[fingerprint] = choice.confirmedByUser();
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (!_complete || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final warning = await widget.onConfirm(
        Map<String, TrackLanguageChoice>.unmodifiable(_choices),
      );
      if (!mounted) return;
      Navigator.of(context).pop(warning);
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认轨道语言'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('此文件含有未标注语言的轨道。确认一次后将为该文件永久记住。'),
              const SizedBox(height: 14),
              for (final track in widget.tracks) ...[
                _trackField(context, track),
                if (track != widget.tracks.last) const SizedBox(height: 10),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _complete && !_saving ? _confirm : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存并继续'),
        ),
      ],
    );
  }

  Widget _trackField(BuildContext context, PendingTrackLanguage track) {
    final label = track.type == EmbeddedTrackType.subtitle ? '字幕轨道' : '音轨';
    final meta = <String>[
      if (track.codecLabel.trim().isNotEmpty) track.codecLabel.trim(),
      if (track.title.trim().isNotEmpty) track.title.trim(),
    ].join(' · ');
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '$label ${track.trackId}',
        helperText: meta.isEmpty ? null : meta,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Autocomplete<TrackLanguageChoice>(
        key: ValueKey('track-language-autocomplete-${track.fingerprint}'),
        displayStringForOption: (choice) => choice.label,
        optionsBuilder: (value) {
          final query = value.text.trim().toLowerCase();
          if (query.isEmpty) return commonTrackLanguageChoices;
          return commonTrackLanguageChoices.where(
            (choice) =>
                choice.label.toLowerCase().contains(query) ||
                choice.code.toLowerCase().contains(query),
          );
        },
        onSelected: (choice) => _setChoice(track.fingerprint, choice),
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            key: ValueKey('track-language-input-${track.fingerprint}'),
            controller: controller,
            focusNode: focusNode,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: '搜索或输入语言',
              border: InputBorder.none,
              isDense: true,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              final choice = _choiceFromText(value);
              if (choice != null) {
                _setChoice(track.fingerprint, choice);
              }
              onFieldSubmitted();
            },
          );
        },
      ),
    );
  }
}
