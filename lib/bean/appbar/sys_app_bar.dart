import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/bean/widget/embedded_native_control_area.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/bean/appbar/desktop_window_controls.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double? toolbarHeight;

  final Widget? title;

  final Color? backgroundColor;

  final double? elevation;

  final ShapeBorder? shape;

  final List<Widget>? actions;

  final Widget? leading;

  final double? leadingWidth;

  final PreferredSizeWidget? bottom;

  final bool needTopOffset;

  final bool showDesktopWindowControls;

  const SysAppBar(
      {super.key,
      this.toolbarHeight,
      this.title,
      this.backgroundColor,
      this.elevation,
      this.shape,
      this.actions,
      this.leading,
      this.leadingWidth,
      this.bottom,
      this.needTopOffset = true,
      this.showDesktopWindowControls = true});

  bool showWindowButton() {
    return GStorage.setting.getTyped<bool>(
      SettingBoxKey.showWindowButton,
      defaultValue: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> acs = [];
    if (actions != null) {
      acs.addAll(actions!);
    }
    if (Utils.isDesktop() && showDesktopWindowControls) {
      // acs.add(IconButton(onPressed: () => windowManager.minimize(), icon: const Icon(Icons.minimize)));
      if (!showWindowButton()) {
        acs.add(const DesktopWindowControls());
      }
    }
    return GestureDetector(
      onPanStart: (_) =>
          (Utils.isDesktop()) ? windowManager.startDragging() : null,
      child: AppBar(
        toolbarHeight: preferredSize.height,
        scrolledUnderElevation: 0.0,
        title: title != null
            ? EmbeddedNativeControlArea(
                requireOffset: needTopOffset,
                child: title!,
              )
            : null,
        centerTitle: false,
        actions: acs.map((e) {
          return EmbeddedNativeControlArea(
            requireOffset: needTopOffset,
            child: e,
          );
        }).toList(),
        leading: leading != null
            ? EmbeddedNativeControlArea(
                requireOffset: needTopOffset,
                child: leading!,
              )
            : Navigator.canPop(context)
                ? EmbeddedNativeControlArea(
                    requireOffset: needTopOffset,
                    child: IconButton(
                      onPressed: () {
                        Navigator.maybePop(context);
                      },
                      icon: Icon(Icons.arrow_back),
                    ),
                  )
                : null,
        leadingWidth: leadingWidth,
        backgroundColor: backgroundColor,
        elevation: elevation,
        shape: shape,
        bottom: bottom,
        automaticallyImplyLeading: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.light
                  ? Brightness.dark
                  : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      ),
    );
  }

  @override
  Size get preferredSize {
    return Size.fromHeight(toolbarHeight ?? kToolbarHeight);
  }
}
