import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_module.dart';
import 'package:kanyingyin/pages/local/local_module.dart';
import 'package:kanyingyin/pages/my/my_module.dart';

class NavigationDestinationConfig {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Module Function() moduleBuilder;

  const NavigationDestinationConfig({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.moduleBuilder,
  });

  String get defaultStartupPath => '/tab$path/';
}

final appNavigationDestinations = <NavigationDestinationConfig>[
  NavigationDestinationConfig(
    path: '/local',
    label: '本地媒体库',
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
      item.defaultStartupPath: item.label,
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
