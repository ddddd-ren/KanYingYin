import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/features/settings/presentation/settings_motion.dart';

/// 设置子页统一框架，负责标题栏、内容宽度与入场衔接。
class KSettingsScaffold extends StatelessWidget {
  const KSettingsScaffold({
    super.key,
    required this.title,
    this.description,
    required this.body,
    this.maxWidth = 920,
    this.actions,
  });

  final String title;
  final String? description;
  final Widget body;
  final double maxWidth;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: Text(title),
        actions: actions,
      ),
      body: _SettingsContentEntrance(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Text(
                      description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsContentEntrance extends StatelessWidget {
  const _SettingsContentEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = SettingsMotion.isReduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: SettingsMotion.duration(
        context,
        SettingsMotion.contentDuration,
      ),
      curve: SettingsMotion.pageCurve,
      child: child,
      builder: (context, progress, child) {
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, reduced ? 0 : 8 * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}

/// 设置页统一滚动容器。
class KSettingsList extends StatelessWidget {
  const KSettingsList({
    super.key,
    required this.sections,
    this.maxWidth = 920,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 32),
  });

  final List<Widget> sections;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView.separated(
          padding: padding,
          itemCount: sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 20),
          itemBuilder: (_, index) => sections[index],
        ),
      ),
    );
  }
}
