import 'package:flutter/material.dart';

import 'log_event_view_data.dart';

class LogFilterBar extends StatelessWidget {
  const LogFilterBar({
    super.key,
    required this.controller,
    required this.filter,
    required this.visibleCount,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final LogEventFilter filter;
  final int visibleCount;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<LogEventFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: controller,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: '搜索摘要或完整原文',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: onClearQuery,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        );
        final filters = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _filterChip('全部', LogEventFilter.all),
            _filterChip('提醒', LogEventFilter.warnings),
            _filterChip('错误', LogEventFilter.errors),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '$visibleCount 条结果',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        );

        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [search, const SizedBox(height: 10), filters],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 14),
            filters,
          ],
        );
      },
    );
  }

  Widget _filterChip(String label, LogEventFilter value) {
    return ChoiceChip(
      label: Text(label),
      selected: filter == value,
      showCheckmark: false,
      onSelected: (_) => onFilterChanged(value),
    );
  }
}
