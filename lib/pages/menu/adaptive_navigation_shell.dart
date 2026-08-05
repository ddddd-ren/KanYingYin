import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';

const double compactNavigationBreakpoint = 640;
const double expandedSidebarBreakpoint = 960;

typedef NavigationWrapper = Widget Function(Widget child);

/// 按窗口宽度切换桌面侧栏、紧凑侧栏和底部导航。
class AdaptiveNavigationShell extends StatelessWidget {
  const AdaptiveNavigationShell({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.content,
    this.topBar,
    this.navigationHidden = false,
    this.navigationWrapper,
    this.onThemeModeChanged,
  });

  final int selectedIndex;
  final List<NavigationDestinationConfig> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget content;
  final Widget? topBar;
  final bool navigationHidden;
  final NavigationWrapper? navigationWrapper;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (navigationHidden) return _contentOnly(context);
        if (constraints.maxWidth < compactNavigationBreakpoint) {
          return _bottomLayout(context);
        }
        return _desktopLayout(
          context,
          expanded: constraints.maxWidth >= expandedSidebarBreakpoint,
        );
      },
    );
  }

  Widget _contentOnly(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Column(
        children: [
          if (topBar != null) topBar!,
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _bottomLayout(BuildContext context) {
    final navigationColor = Theme.of(context).colorScheme.surfaceContainerLow;
    final visibleDestinations = <({
      int globalIndex,
      NavigationDestinationConfig destination,
    })>[
      for (var index = 0; index < destinations.length; index++)
        if (destinations[index].showInBottomNavigation)
          (globalIndex: index, destination: destinations[index]),
    ];
    final categoryDestinations = <({
      int globalIndex,
      NavigationDestinationConfig destination,
    })>[
      for (var index = 0; index < destinations.length; index++)
        if (!destinations[index].showInBottomNavigation)
          (globalIndex: index, destination: destinations[index]),
    ];
    final selectedCoreIndex = visibleDestinations.indexWhere(
      (item) => item.globalIndex == selectedIndex,
    );
    final categorySelected = categoryDestinations.any(
      (item) => item.globalIndex == selectedIndex,
    );
    final selectedBottomIndex = categorySelected
        ? 0
        : selectedCoreIndex < 0
            ? 1
            : selectedCoreIndex + 1;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        key: const ValueKey<String>('mobile-safe-content'),
        bottom: false,
        child: Column(
          children: [
            if (topBar != null) topBar!,
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: GlassSurface(
        key: const ValueKey<String>('compact-bottom-navigation-surface'),
        borderRadius: BorderRadius.zero,
        blurSigma: 18,
        color: navigationColor.withValues(alpha: 0.78),
        border: Border(
          top: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.32),
          ),
        ),
        child: SafeArea(
          key: const ValueKey<String>('compact-bottom-navigation-safe-area'),
          top: false,
          child: NavigationBar(
            key: const ValueKey<String>('compact-bottom-navigation'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            selectedIndex: selectedBottomIndex,
            onDestinationSelected: (index) async {
              if (index == 0) {
                final selected = await _showCategorySelector(
                  context,
                  categoryDestinations,
                );
                if (selected != null) onDestinationSelected(selected);
                return;
              }
              onDestinationSelected(
                visibleDestinations[index - 1].globalIndex,
              );
            },
            destinations: [
              const NavigationDestination(
                selectedIcon: Icon(Icons.category_rounded),
                icon: Icon(Icons.category_outlined),
                label: '分类',
              ),
              for (final item in visibleDestinations)
                NavigationDestination(
                  selectedIcon: Icon(item.destination.selectedIcon),
                  icon: Icon(item.destination.icon),
                  label: item.destination.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _showCategorySelector(
    BuildContext context,
    List<
            ({
              int globalIndex,
              NavigationDestinationConfig destination,
            })>
        categories,
  ) {
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in categories)
                ListTile(
                  leading: Icon(
                    selectedIndex == item.globalIndex
                        ? item.destination.selectedIcon
                        : item.destination.icon,
                  ),
                  title: Text(item.destination.label),
                  trailing: selectedIndex == item.globalIndex
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(item.globalIndex),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopLayout(BuildContext context, {required bool expanded}) {
    final colors = Theme.of(context).colorScheme;
    final primaryDestinations =
        destinations.take(destinations.length - 1).toList();
    final selectedPrimaryIndex =
        selectedIndex < primaryDestinations.length ? selectedIndex : null;
    final navigation = expanded
        ? _ExpandedSidebar(
            key: const ValueKey<String>('desktop-sidebar-expanded'),
            selectedIndex: selectedIndex,
            destinations: destinations,
            onDestinationSelected: onDestinationSelected,
            onThemeModeChanged: onThemeModeChanged,
          )
        : _CompactSidebar(
            key: const ValueKey<String>('desktop-sidebar-compact'),
            selectedIndex: selectedPrimaryIndex,
            destinations: primaryDestinations,
            onDestinationSelected: onDestinationSelected,
            onSettingsPressed: () => onDestinationSelected(
              destinations.length - 1,
            ),
            onThemeModeChanged: onThemeModeChanged,
          );
    final wrappedNavigation = navigationWrapper?.call(navigation) ?? navigation;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: Column(
        children: [
          if (topBar != null) topBar!,
          Expanded(
            child: Row(
              children: [
                wrappedNavigation,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: GlassSurface(
                      key: const ValueKey<String>('navigation-content-surface'),
                      borderRadius: BorderRadius.circular(12),
                      blurSigma: 14,
                      color: colors.surface.withValues(alpha: 0.66),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.45),
                      ),
                      child: content,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSidebar extends StatelessWidget {
  const _CompactSidebar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.onSettingsPressed,
    this.onThemeModeChanged,
  });

  final int? selectedIndex;
  final List<NavigationDestinationConfig> destinations;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettingsPressed;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Stack(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            labelType: NavigationRailLabelType.none,
            groupAlignment: -0.72,
            leading: const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 18),
              child: Icon(Icons.play_circle_fill_rounded, size: 30),
            ),
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final item in destinations)
                NavigationRailDestination(
                  selectedIcon: Icon(item.selectedIcon),
                  icon: Icon(item.icon),
                  label: Text(item.label),
                ),
            ],
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 12,
            child: _CompactSidebarTools(
              onSettingsPressed: onSettingsPressed,
              onThemeModeChanged: onThemeModeChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.onThemeModeChanged,
  });

  final int selectedIndex;
  final List<NavigationDestinationConfig> destinations;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primaryDestinations = destinations.take(destinations.length - 1);
    final utilityIndex = destinations.length - 1;
    return SizedBox(
      width: 216,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(14),
        blurSigma: 16,
        color: colors.surfaceContainerLowest.withValues(alpha: 0.76),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 18),
                child: Row(
                  children: [
                    Icon(Icons.play_circle_fill_rounded, size: 30),
                    SizedBox(width: 10),
                    Text(
                      '看影音',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              for (var index = 0;
                  index < primaryDestinations.length;
                  index++) ...[
                _SidebarDestination(
                  destination: destinations[index],
                  selected: selectedIndex == index,
                  onTap: () => onDestinationSelected(index),
                ),
                const SizedBox(height: 4),
              ],
              const Spacer(),
              if (utilityIndex >= 0)
                Row(
                  children: [
                    Expanded(
                      child: _SidebarDestination(
                        destination: destinations[utilityIndex],
                        selected: selectedIndex == utilityIndex,
                        onTap: () => onDestinationSelected(utilityIndex),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _ThemeModeButton(
                      onChanged: onThemeModeChanged,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactSidebarTools extends StatelessWidget {
  const _CompactSidebarTools({
    required this.onSettingsPressed,
    this.onThemeModeChanged,
  });

  final VoidCallback onSettingsPressed;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('desktop-sidebar-compact-tools'),
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '设置',
          onPressed: onSettingsPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 40),
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
        _ThemeModeButton(
          onChanged: onThemeModeChanged,
          compact: true,
        ),
      ],
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({this.onChanged, this.compact = false});

  final ValueChanged<ThemeMode>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? '切换浅色模式' : '切换深色模式',
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
      constraints:
          compact ? const BoxConstraints.tightFor(width: 32, height: 40) : null,
      onPressed: () {
        final next = dark ? ThemeMode.light : ThemeMode.dark;
        if (onChanged != null) {
          onChanged!(next);
        }
      },
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: compact ? 20 : null,
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestinationConfig destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 21,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
