import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/presentation/settings_motion.dart';

/// 无交互的设置说明行。
class KSettingsTile extends StatelessWidget {
  const KSettingsTile({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.trailing,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _SettingsTileContent(
      title: title,
      description: description,
      leading: leading,
      trailing: trailing,
      enabled: true,
    );
  }
}

class KSettingsNavigationTile extends StatelessWidget {
  const KSettingsNavigationTile({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.value,
    this.enabled = true,
    required this.onPressed,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final Widget? value;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        onTap: enabled ? onPressed : null,
        child: _InteractiveSettingsTile(
          enabled: enabled,
          onPressed: onPressed,
          child: _SettingsTileContent(
            title: title,
            description: description,
            leading: leading,
            enabled: enabled,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null) ...[
                  Flexible(child: value!),
                  const SizedBox(width: 8),
                ],
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KSettingsSwitchTile extends StatelessWidget {
  const KSettingsSwitchTile({
    super.key,
    required this.title,
    this.description,
    this.leading,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void toggle() => onChanged(!value);
    return MergeSemantics(
      child: Semantics(
        container: true,
        enabled: enabled,
        toggled: value,
        onTap: enabled ? toggle : null,
        child: _InteractiveSettingsTile(
          enabled: enabled,
          onPressed: toggle,
          child: _SettingsTileContent(
            title: title,
            description: description,
            leading: leading,
            enabled: enabled,
            trailing: ExcludeSemantics(
              child: Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KSettingsRadioTile<T> extends StatelessWidget {
  const KSettingsRadioTile({
    super.key,
    required this.title,
    this.description,
    this.leading,
    required this.value,
    required this.groupValue,
    this.enabled = true,
    required this.onChanged,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final T value;
  final T? groupValue;
  final bool enabled;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    void select() => onChanged(value);
    return MergeSemantics(
      child: Semantics(
        container: true,
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: enabled,
        onTap: enabled ? select : null,
        child: _InteractiveSettingsTile(
          enabled: enabled,
          onPressed: select,
          child: _SettingsTileContent(
            title: title,
            description: description,
            leading: leading,
            enabled: enabled,
            trailing: ExcludeSemantics(
              child: RadioGroup<T>(
                groupValue: groupValue,
                onChanged: onChanged,
                child: Radio<T>(
                  value: value,
                  enabled: enabled,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KSettingsStatusBadge extends StatelessWidget {
  const KSettingsStatusBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _InteractiveSettingsTile extends StatefulWidget {
  const _InteractiveSettingsTile({
    required this.enabled,
    required this.onPressed,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_InteractiveSettingsTile> createState() =>
      _InteractiveSettingsTileState();
}

class _InteractiveSettingsTileState extends State<_InteractiveSettingsTile> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = SettingsMotion.isReduced(context);
    final scale = reduced ? 1.0 : (_pressed ? 0.99 : 1.0);
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => _setHovered(true) : null,
      onExit: widget.enabled ? (_) => _setHovered(false) : null,
      child: AnimatedScale(
        scale: scale,
        duration: SettingsMotion.duration(
          context,
          _pressed
              ? SettingsMotion.pressDuration
              : SettingsMotion.hoverDuration,
        ),
        curve: SettingsMotion.hoverCurve,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? widget.onPressed : null,
            onHighlightChanged: widget.enabled ? _setPressed : null,
            focusColor: scheme.primary.withValues(alpha: 0.12),
            hoverColor: Colors.transparent,
            splashColor: scheme.primary.withValues(alpha: 0.12),
            child: AnimatedContainer(
              duration: SettingsMotion.duration(
                context,
                SettingsMotion.hoverDuration,
              ),
              curve: SettingsMotion.hoverCurve,
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.075)
                  : Colors.transparent,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTileContent extends StatelessWidget {
  const _SettingsTileContent({
    required this.title,
    required this.description,
    required this.leading,
    required this.trailing,
    required this.enabled,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final opacity = enabled ? 1.0 : 0.45;
    return Opacity(
      opacity: opacity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              if (leading != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                    child: leading!,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      child: title,
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      DefaultTextStyle.merge(
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                        child: description!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Flexible(child: trailing!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
