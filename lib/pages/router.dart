import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';

class MenuRouteItem {
  final String path;
  final Module module;

  const MenuRouteItem({
    required this.path,
    required this.module,
  });
}

class MenuRoute {
  final List<MenuRouteItem> menuList;

  const MenuRoute(this.menuList);

  int get size => menuList.length;

  List<Module> get moduleList {
    return menuList.map((e) => e.module).toList();
  }

  List<ModuleRoute> get routes {
    return menuList.map((e) => ModuleRoute(e.path, module: e.module)).toList();
  }

  String getPath(int index) {
    return menuList[index].path;
  }
}

final MenuRoute menu = MenuRoute(
  appNavigationDestinations
      .map((item) => MenuRouteItem(
            path: item.path,
            module: item.moduleBuilder(),
          ))
      .toList(),
);
