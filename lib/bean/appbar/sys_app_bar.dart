import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/embedded_native_control_area.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/platform/android/android_system_ui_surface.dart';
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
    final appBar = AppBar(
      toolbarHeight: preferredSize.height,
      scrolledUnderElevation: 0.0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      flexibleSpace: GlassSurface(
        borderRadius: BorderRadius.zero,
        blurSigma: 20,
        color: (backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerLow)
            .withValues(alpha: 0.78),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.32),
          ),
        ),
        child: const SizedBox.expand(),
      ),
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
      elevation: elevation,
      shape: shape,
      bottom: bottom,
      automaticallyImplyLeading: false,
      systemOverlayStyle: androidAppSystemUiStyle(
        Theme.of(context).brightness,
      ),
    );
    if (!Utils.isDesktop()) return appBar;
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: appBar,
    );
  }

  @override
  Size get preferredSize {
    return Size.fromHeight(toolbarHeight ?? kToolbarHeight);
  }
}
