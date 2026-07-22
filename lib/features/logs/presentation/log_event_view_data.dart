import 'dart:collection';

enum LogEventCategory { normal, warning, error, other }

enum LogEventFilter { all, warnings, errors }

class LogEventViewData {
  const LogEventViewData({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.summary,
    required this.rawText,
    required this.sourceIndex,
  });

  final int id;
  final DateTime? timestamp;
  final String level;
  final LogEventCategory category;
  final String summary;
  final String rawText;
  final int sourceIndex;
}

abstract final class LogEventParser {
  static final RegExp _header = RegExp(
    r'^\[([^\]]+)\]\s+(TRACE|DEBUG|INFO|WARNING|ERROR|FATAL|PLAYER)\s*$',
  );
  static final RegExp _compactLine = RegExp(
    r'^\[[^\]]+\]\s+.*?\b(?:TRACE|DEBUG|INFO|WARNING|ERROR|FATAL)\s+(.*)$',
  );
  static final RegExp _frameOnly = RegExp(r'^[┌┐└┘├┤┄─│╡═\s]+$');
  static final RegExp _framePrefix = RegExp(r'^[┌┐└┘├┤┄─│╡═\s]+');

  static List<LogEventViewData> parse(String content) {
    if (content.trim().isEmpty) return const [];
    final chunks = <_LogChunk>[];
    _LogChunk? current;
    for (final line in content.split('\n')) {
      final match = _header.firstMatch(line.trimRight());
      if (match != null) {
        if (current != null) chunks.add(current);
        current = _LogChunk(
          header: line,
          timestampText: match.group(1)!,
          level: match.group(2)!,
          lines: <String>[],
          sourceIndex: chunks.length,
        );
      } else if (current == null) {
        if (line.trim().isEmpty) continue;
        current = _LogChunk(
          header: '',
          timestampText: '',
          level: 'OTHER',
          lines: <String>[line],
          sourceIndex: chunks.length,
        );
      } else {
        current.lines.add(line);
      }
    }
    if (current != null) chunks.add(current);

    final events = chunks.map(_toViewData).toList()
      ..sort((left, right) {
        if (left.timestamp != null && right.timestamp != null) {
          return right.timestamp!.compareTo(left.timestamp!);
        }
        if (left.timestamp == null && right.timestamp == null) {
          return left.sourceIndex.compareTo(right.sourceIndex);
        }
        return left.timestamp == null ? 1 : -1;
      });
    return UnmodifiableListView(events);
  }

  static LogEventViewData _toViewData(_LogChunk chunk) {
    final rawLines = <String>[
      if (chunk.header.isNotEmpty) chunk.header,
      ...chunk.lines,
    ];
    return LogEventViewData(
      id: chunk.sourceIndex,
      timestamp: DateTime.tryParse(chunk.timestampText),
      level: chunk.level,
      category: _categoryFor(chunk.level),
      summary: _summaryFor(chunk.lines, chunk.level),
      rawText: rawLines.join('\n').trimRight(),
      sourceIndex: chunk.sourceIndex,
    );
  }

  static LogEventCategory _categoryFor(String level) => switch (level) {
        'WARNING' => LogEventCategory.warning,
        'ERROR' || 'FATAL' => LogEventCategory.error,
        'TRACE' || 'DEBUG' || 'INFO' || 'PLAYER' => LogEventCategory.normal,
        _ => LogEventCategory.other,
      };

  static String _summaryFor(List<String> lines, String level) {
    for (final line in lines) {
      final compact = _compactLine.firstMatch(line.trim())?.group(1)?.trim();
      if (compact?.isNotEmpty == true) return compact!;
      if (_frameOnly.hasMatch(line)) continue;
      final cleaned = line.replaceFirst(_framePrefix, '').trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    return level == 'OTHER' ? '其他记录' : '$level 记录';
  }
}

abstract final class LogEventQuery {
  static List<LogEventViewData> apply(
    Iterable<LogEventViewData> events, {
    LogEventFilter filter = LogEventFilter.all,
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    return List<LogEventViewData>.unmodifiable(
      events.where((event) {
        final categoryMatches = switch (filter) {
          LogEventFilter.all => true,
          LogEventFilter.warnings => event.category == LogEventCategory.warning,
          LogEventFilter.errors => event.category == LogEventCategory.error,
        };
        if (!categoryMatches) return false;
        if (needle.isEmpty) return true;
        return '${event.summary}\n${event.rawText}'.toLowerCase().contains(
              needle,
            );
      }),
    );
  }
}

class _LogChunk {
  _LogChunk({
    required this.header,
    required this.timestampText,
    required this.level,
    required this.lines,
    required this.sourceIndex,
  });

  final String header;
  final String timestampText;
  final String level;
  final List<String> lines;
  final int sourceIndex;
}
