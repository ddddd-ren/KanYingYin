import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/history/presentation/history_module.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/media_category_module.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_module.dart';
import 'package:kanyingyin/pages/local/local_module.dart';
import 'package:kanyingyin/pages/my/my_module.dart';

class NavigationDestinationConfig {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Module Function() moduleBuilder;
  final bool showInBottomNavigation;
  final bool canBeStartupPage;

  const NavigationDestinationConfig({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.moduleBuilder,
    this.showInBottomNavigation = true,
    this.canBeStartupPage = true,
  });

  String get defaultStartupPath => '/tab$path/';
}

final appNavigationDestinations = <NavigationDestinationConfig>[
  NavigationDestinationConfig(
    path: '/movies',
    label: '电影',
    icon: Icons.movie_outlined,
    selectedIcon: Icons.movie_rounded,
    moduleBuilder: () => MediaCategoryModule(MediaLibraryCategory.movie),
    showInBottomNavigation: false,
    canBeStartupPage: false,
  ),
  NavigationDestinationConfig(
    path: '/anime',
    label: '动漫',
    icon: Icons.animation_outlined,
    selectedIcon: Icons.animation_rounded,
    moduleBuilder: () => MediaCategoryModule(MediaLibraryCategory.anime),
    showInBottomNavigation: false,
    canBeStartupPage: false,
  ),
  NavigationDestinationConfig(
    path: '/tv-series',
    label: '电视剧',
    icon: Icons.live_tv_outlined,
    selectedIcon: Icons.live_tv_rounded,
    moduleBuilder: () => MediaCategoryModule(MediaLibraryCategory.tvSeries),
    showInBottomNavigation: false,
    canBeStartupPage: false,
  ),
  NavigationDestinationConfig(
    path: '/local',
    label: '媒体库',
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
    moduleBuilder: LocalModule.new,
  ),
  NavigationDestinationConfig(
    path: '/cloud',
    label: '网盘媒体库',
    icon: Icons.cloud_outlined,
    selectedIcon: Icons.cloud_rounded,
    moduleBuilder: CloudResourcesModule.new,
  ),
  NavigationDestinationConfig(
    path: '/history',
    label: '观看历史',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history_rounded,
    moduleBuilder: HistoryModule.new,
  ),
  NavigationDestinationConfig(
    path: '/my',
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    moduleBuilder: MyModule.new,
  ),
];

const defaultStartupPage = '/tab/local/';

Map<String, String> get defaultStartupPageLabels {
  return {
    for (final item in appNavigationDestinations)
      if (item.canBeStartupPage) item.defaultStartupPath: item.label,
  };
}

bool isValidStartupPage(String page) {
  return defaultStartupPageLabels.containsKey(page);
}

int navigationIndexForStartupPage(String page) {
  return appNavigationDestinations.indexWhere(
    (item) => item.defaultStartupPath == page,
  );
}

int resolveNavigationIndex(String? page) {
  final selected = page == null ? -1 : navigationIndexForStartupPage(page);
  if (selected >= 0) return selected;
  final fallback = navigationIndexForStartupPage(defaultStartupPage);
  return fallback >= 0 ? fallback : 0;
}
