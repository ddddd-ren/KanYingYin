import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/widget/embedded_native_control_area.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/tv/presentation/tv_back_navigation_guard.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/pages/router.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/bean/appbar/desktop_window_controls.dart';
import 'package:kanyingyin/bean/appbar/drag_to_move_bar.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:provider/provider.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key});

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class NavigationBarState extends ChangeNotifier {
  late int _selectedIndex = getDefaultSelectedIndex();
  bool _isHide = false;

  int get selectedIndex => _selectedIndex;

  bool get isHide => _isHide;

  int getDefaultSelectedIndex() {
    final defaultPage = Modular.get<TypedSettings>().get(
      SettingBoxKey.defaultStartupPage,
      defaultValue: defaultStartupPage,
    );
    return resolveNavigationIndex(defaultPage is String ? defaultPage : null);
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
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => NavigationBarState(),
      child: Consumer<NavigationBarState>(
        builder: (context, state, _) {
          final capabilities = detectAppPlatform();
          return TvBackNavigationGuard(
            enabled: capabilities.isAndroidTv,
            child: AdaptiveNavigationShell(
              capabilities: capabilities,
              selectedIndex: state.selectedIndex,
              destinations: appNavigationDestinations,
              navigationHidden: state.isHide,
              topBar:
                  _showCustomWindowControls ? _desktopTitleBar(context) : null,
              navigationWrapper: (child) => EmbeddedNativeControlArea(
                child: AnimatedOpacity(
                  duration: StyleString.fastAnimationDuration,
                  opacity: state.isHide ? 0 : 1,
                  child: child,
                ),
              ),
              onDestinationSelected: (index) {
                state.updateSelectedIndex(index);
                Modular.to.navigate('/tab${menu.getPath(index)}/');
              },
              onThemeModeChanged: (mode) async {
                final themeProvider =
                    Provider.of<ThemeProvider>(context, listen: false);
                themeProvider.setThemeMode(mode);
                await Modular.get<TypedSettings>().put(
                  SettingBoxKey.themeMode,
                  mode == ThemeMode.dark ? 'dark' : 'light',
                );
              },
              content: const RouterOutlet(),
            ),
          );
        },
      ),
    );
  }

  bool get _showCustomWindowControls =>
      Utils.isDesktop() &&
      !Modular.get<TypedSettings>().getTyped<bool>(
        SettingBoxKey.showWindowButton,
        defaultValue: false,
      );

  Widget _desktopTitleBar(BuildContext context) {
    return GlassSurface(
      key: const ValueKey<String>('desktop-title-bar-glass'),
      borderRadius: BorderRadius.zero,
      blurSigma: 20,
      color: Theme.of(context).colorScheme.surfaceContainer.withValues(
            alpha: 0.76,
          ),
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.32),
        ),
      ),
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
