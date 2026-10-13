import 'package:flutter/material.dart';

/// 媒体库页面共用的标题、搜索和操作排列。
/// 页面仍负责提供筛选、排序、刷新等具体动作，工具栏只处理布局。
class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    super.key,
    required this.title,
    required this.icon,
    this.count,
    this.status,
    this.searchController,
    this.searchField,
    this.searchHint = '搜索媒体',
    this.onSearchChanged,
    this.onClearSearch,
    this.leading,
    this.filter,
    this.sort,
    this.refresh,
    this.actions = const <Widget>[],
    this.titleKey,
    this.searchKey,
  });

  final String title;
  final IconData icon;
  final int? count;
  final String? status;
  final TextEditingController? searchController;
  final Widget? searchField;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onClearSearch;
  final Widget? leading;
  final Widget? filter;
  final Widget? sort;
  final Widget? refresh;
  final List<Widget> actions;
  final Key? titleKey;
  final Key? searchKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleRow = Row(
      children: [
        Icon(icon, color: colors.primary),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            key: titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 10),
          Text(
            '$count 部',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.outline),
          ),
        ],
        if (status case final value? when value.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.outline),
            ),
          ),
        ],
      ],
    );

    final search = searchField ??
        (searchController == null
            ? null
            : SizedBox(
                height: 40,
                child: TextField(
                  key: searchKey,
                  controller: searchController,
                  onChanged: onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: searchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon:
                        searchController!.text.isEmpty || onClearSearch == null
                            ? null
                            : IconButton(
                                tooltip: '清空搜索',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: onClearSearch,
                              ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ));
    final actions = <Widget>[
      if (filter != null) filter!,
      if (sort != null) sort!,
      if (refresh != null) refresh!,
      ...this.actions,
    ];

    return Padding(
      key: const ValueKey<String>('library-toolbar'),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleRow,
                const SizedBox(height: 6),
                if (search != null) ...[
                  search,
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    if (leading != null) Expanded(child: leading!),
                    if (leading != null && actions.isNotEmpty)
                      const SizedBox(width: 4),
                    ...actions,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleRow),
              if (leading != null) SizedBox(width: 220, child: leading!),
              if (search != null) ...[
                const SizedBox(width: 8),
                SizedBox(width: 240, child: search),
              ],
              const SizedBox(width: 4),
              ...actions,
            ],
          );
        },
      ),
    );
  }
}
