import 'package:flutter/material.dart';
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
  });

  final int selectedIndex;
  final List<NavigationDestinationConfig> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget content;
  final Widget? topBar;
  final bool navigationHidden;
  final NavigationWrapper? navigationWrapper;

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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          if (topBar != null) topBar!,
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const ValueKey<String>('compact-bottom-navigation'),
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          for (final item in destinations)
            NavigationDestination(
              selectedIcon: Icon(item.selectedIcon),
              icon: Icon(item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }

  Widget _desktopLayout(BuildContext context, {required bool expanded}) {
    final colors = Theme.of(context).colorScheme;
    final navigation = expanded
        ? _ExpandedSidebar(
            key: const ValueKey<String>('desktop-sidebar-expanded'),
            selectedIndex: selectedIndex,
            destinations: destinations,
            onDestinationSelected: onDestinationSelected,
          )
        : NavigationRail(
            key: const ValueKey<String>('desktop-sidebar-compact'),
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
                    child: DecoratedBox(
                      key: const ValueKey<String>('navigation-content-surface'),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: content,
                      ),
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

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<NavigationDestinationConfig> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primaryDestinations = destinations.take(destinations.length - 1);
    final utilityIndex = destinations.length - 1;
    return SizedBox(
      width: 216,
      child: Material(
        color: colors.surfaceContainerLowest,
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
                _SidebarDestination(
                  destination: destinations[utilityIndex],
                  selected: selectedIndex == utilityIndex,
                  onTap: () => onDestinationSelected(utilityIndex),
                ),
            ],
          ),
        ),
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
