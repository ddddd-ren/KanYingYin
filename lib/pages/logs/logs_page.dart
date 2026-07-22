import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/features/logs/presentation/logs_presentation.dart';
import 'package:kanyingyin/utils/log_archive_reader.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, this.reader});

  final LogArchiveReader? reader;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _expandedEventIds = <int>{};
  late final LogArchiveReader _reader;

  bool _isLoading = true;
  bool _hasError = false;
  String _fullContent = '';
  List<LogEventViewData> _allEvents = const [];
  LogEventFilter _filter = LogEventFilter.all;
  String _query = '';
  int _visibleLimit = _initialLoadCount;

  static const int _initialLoadCount = 50;
  static const int _loadMoreCount = 100;

  List<LogEventViewData> get _filteredEvents => LogEventQuery.apply(
        _allEvents,
        filter: _filter,
        query: _query,
      );

  @override
  void initState() {
    super.initState();
    _reader = widget.reader ?? LogArchiveReader();
    _scrollController.addListener(_onScroll);
    unawaited(_loadLogs());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final filteredCount = _filteredEvents.length;
    if (_visibleLimit >= filteredCount) return;

    final position = _scrollController.position;
    final threshold = position.maxScrollExtent * 0.8;
    if (position.pixels >= threshold) _loadMoreEvents(filteredCount);
  }

  Future<void> _loadLogs() async {
    try {
      final content = await _reader.readAll();
      if (!mounted) return;
      setState(() {
        _fullContent = content;
        _allEvents = LogEventParser.parse(content);
        _visibleLimit = _initialLoadCount;
        _hasError = false;
        _isLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _loadMoreEvents(int filteredCount) {
    Future.microtask(() {
      if (!mounted || _visibleLimit >= filteredCount) return;
      setState(() {
        _visibleLimit = (_visibleLimit + _loadMoreCount).clamp(
          0,
          filteredCount,
        );
      });
    });
  }

  void _changeQuery(String value) {
    setState(() {
      _query = value;
      _visibleLimit = _initialLoadCount;
      _expandedEventIds.clear();
    });
  }

  void _clearQuery() {
    _searchController.clear();
    _changeQuery('');
  }

  void _changeFilter(LogEventFilter value) {
    setState(() {
      _filter = value;
      _visibleLimit = _initialLoadCount;
      _expandedEventIds.clear();
    });
  }

  void _toggleEvent(int eventId) {
    setState(() {
      if (!_expandedEventIds.add(eventId)) {
        _expandedEventIds.remove(eventId);
      }
    });
  }

  Future<void> _clearLogs() async {
    try {
      await _reader.clear();
      if (!mounted) return;

      _searchController.clear();
      setState(() {
        _allEvents = const [];
        _fullContent = '';
        _query = '';
        _filter = LogEventFilter.all;
        _visibleLimit = _initialLoadCount;
        _expandedEventIds.clear();
        _hasError = false;
      });
    } on Object {
      if (!mounted) return;
      AppDialog.showToast(message: '清空日志失败，请稍后重试');
    }
  }

  Future<void> _copyLogs() async {
    try {
      await Clipboard.setData(ClipboardData(text: _fullContent));
      if (!mounted) return;
      AppDialog.showToast(message: '已复制到剪贴板');
    } on Object {
      if (!mounted) return;
      AppDialog.showToast(message: '复制日志失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text('运行记录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: AnimatedSwitcher(
              duration: LogMotion.duration(context, LogMotion.stateDuration),
              switchInCurve: LogMotion.curve,
              switchOutCurve: LogMotion.curve,
              child: _buildContent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const LogStatePanel(
        key: ValueKey('logs-page-loading'),
        kind: LogStateKind.loading,
      );
    }
    if (_hasError) {
      return const LogStatePanel(
        key: ValueKey('logs-page-error'),
        kind: LogStateKind.error,
      );
    }
    if (_allEvents.isEmpty) {
      return const LogStatePanel(
        key: ValueKey('logs-page-empty'),
        kind: LogStateKind.empty,
      );
    }

    final filteredEvents = _filteredEvents;
    final visibleEvents =
        filteredEvents.take(_visibleLimit).toList(growable: false);
    final warnings = _allEvents
        .where((event) => event.category == LogEventCategory.warning)
        .length;
    final errors = _allEvents
        .where((event) => event.category == LogEventCategory.error)
        .length;

    return Column(
      key: const ValueKey('logs-page-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '诊断概览',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Tooltip(
              message: '复制全部',
              child: OutlinedButton.icon(
                onPressed: _copyLogs,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('复制全部'),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '清空日志',
              child: TextButton.icon(
                onPressed: _clearLogs,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('清空'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LogOverviewPanel(
          total: _allEvents.length,
          warnings: warnings,
          errors: errors,
        ),
        const SizedBox(height: 12),
        LogFilterBar(
          controller: _searchController,
          filter: _filter,
          visibleCount: filteredEvents.length,
          onQueryChanged: _changeQuery,
          onClearQuery: _clearQuery,
          onFilterChanged: _changeFilter,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filteredEvents.isEmpty
              ? const LogStatePanel(kind: LogStateKind.noResults)
              : ListView.separated(
                  controller: _scrollController,
                  itemCount: visibleEvents.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final event = visibleEvents[index];
                    return LogEventTile(
                      key: ValueKey('log-event-${event.id}'),
                      event: event,
                      expanded: _expandedEventIds.contains(event.id),
                      onToggle: () => _toggleEvent(event.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
