import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/widget/embedded_native_control_area.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/pages/router.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/bean/appbar/desktop_window_controls.dart';
import 'package:kanyingyin/bean/appbar/drag_to_move_bar.dart';
import 'package:provider/provider.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key});

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class NavigationBarState extends ChangeNotifier {
  late int _selectedIndex = getDefaultSelectedIndex();
  bool _isHide = false;
  bool _isBottom = false;

  int get selectedIndex => _selectedIndex;

  bool get isHide => _isHide;

  bool get isBottom => _isBottom;

  int getDefaultSelectedIndex() {
    final defaultPage = GStorage.setting.get(
      SettingBoxKey.defaultStartupPage,
      defaultValue: defaultStartupPage,
    );
    final index =
        defaultPage is String ? navigationIndexForStartupPage(defaultPage) : -1;
    return index < 0 ? 0 : index;
  }

  void updateSelectedIndex(int pageIndex) {
    if (_selectedIndex == pageIndex) return;
    notifyListeners();
    Future.delayed(StyleString.fastAnimationDuration, () {
      _selectedIndex = pageIndex;
      notifyListeners();
    });
  }

  void hideNavigate() {
    _isHide = true;
    notifyListeners();
  }

  void showNavigate() {
    _isHide = false;
    notifyListeners();
  }
}

class _ScaffoldMenu extends State<ScaffoldMenu> {
  final PageController _page = PageController();

  static List<Widget> get _bottomDestinations {
    return [
      for (final item in appNavigationDestinations)
        NavigationDestination(
          selectedIcon: Icon(item.selectedIcon),
          icon: Icon(item.icon),
          label: item.label,
        ),
    ];
  }

  static List<NavigationRailDestination> get _railDestinations {
    return [
      for (final item in appNavigationDestinations)
        NavigationRailDestination(
          selectedIcon: Icon(item.selectedIcon),
          icon: Icon(item.icon),
          label: Text(item.label),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => NavigationBarState(),
      child: Consumer<NavigationBarState>(
        builder: (context, state, _) {
          return OrientationBuilder(
            builder: (context, orientation) {
              state._isBottom = orientation == Orientation.portrait;
              return orientation != Orientation.portrait
                  ? sideMenuWidget(context, state)
                  : bottomMenuWidget(context, state);
            },
          );
        },
      ),
    );
  }

  Widget bottomMenuWidget(BuildContext context, NavigationBarState state) {
    return Scaffold(
      body: Column(
        children: [
          if (_showCustomWindowControls) _desktopTitleBar(context),
          Expanded(
            child: AnimatedContainer(
              duration: StyleString.fastAnimationDuration,
              curve: StyleString.defaultCurve,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: PageView.builder(
                physics: const NeverScrollableScrollPhysics(),
                controller: _page,
                itemCount: menu.size,
                itemBuilder: (_, __) => const RouterOutlet(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: state.isHide
          ? const SizedBox(height: 0)
          : AnimatedOpacity(
              duration: StyleString.fastAnimationDuration,
              opacity: state.isHide ? 0.0 : 1.0,
              child: NavigationBar(
                destinations: _bottomDestinations,
                selectedIndex: state.selectedIndex,
                onDestinationSelected: (int index) {
                  state.updateSelectedIndex(index);
                  Modular.to.navigate('/tab${menu.getPath(index)}/');
                },
              ),
            ),
    );
  }

  Widget sideMenuWidget(BuildContext context, NavigationBarState state) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Column(
        children: [
          if (_showCustomWindowControls) _desktopTitleBar(context),
          Expanded(
            child: Row(
              children: [
                EmbeddedNativeControlArea(
                  child: AnimatedOpacity(
                    duration: StyleString.fastAnimationDuration,
                    opacity: state.isHide ? 0.0 : 1.0,
                    child: NavigationRail(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainer,
                      groupAlignment: 0.0,
                      labelType: NavigationRailLabelType.selected,
                      destinations: _railDestinations,
                      selectedIndex: state.selectedIndex,
                      onDestinationSelected: (int index) {
                        state.updateSelectedIndex(index);
                        Modular.to.navigate('/tab${menu.getPath(index)}/');
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedContainer(
                    duration: StyleString.fastAnimationDuration,
                    curve: StyleString.defaultCurve,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20.0),
                        bottomLeft: Radius.circular(20.0),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20.0),
                        bottomLeft: Radius.circular(20.0),
                      ),
                      child: PageView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: menu.size,
                        itemBuilder: (_, __) => const RouterOutlet(),
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

  bool get _showCustomWindowControls =>
      Utils.isDesktop() &&
      !GStorage.setting
          .get(SettingBoxKey.showWindowButton, defaultValue: false);

  Widget _desktopTitleBar(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(
        children: [
          const Expanded(
            child: DragToMoveArea(child: SizedBox(height: 40)),
          ),
          const DesktopWindowControls(),
        ],
      ),
    );
  }
}
