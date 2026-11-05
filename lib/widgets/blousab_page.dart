import 'package:flutter/material.dart';

import 'blousab_visuals.dart';

/// Full-screen page that follows the same neon design as the main tabs
/// (top bar with glowing title, deep background). Used by every secondary
/// screen so none of them falls back to the old Material look.
class BlousabPage extends StatelessWidget {
  const BlousabPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.floating,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool showBack;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040813),
      floatingActionButton: floating,
      body: BlousabScreenFrame(
        child: SafeArea(
          child: Column(children: [
            BlousabTopBar(
              titleWidget: BlousabGlowTitle(title, size: 25),
              start: [
                if (showBack)
                  BlousabSquareIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'رجوع',
                    onTap: () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: 38),
              ],
              end: actions.isEmpty ? const [SizedBox(width: 38)] : actions,
            ),
            Expanded(child: child),
          ]),
        ),
      ),
    );
  }
}

/// Section heading used above groups.
class BlousabSectionLabel extends StatelessWidget {
  const BlousabSectionLabel(this.text, {super.key, this.color = const Color(0xFF28C7FF)});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 7),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(text, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );
}

/// Neon rounded group that holds several rows.
class BlousabSettingsGroup extends StatelessWidget {
  const BlousabSettingsGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 12), color: const Color(0xFF1E2F6B)));
      }
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1536), Color(0xFF080F2A)],
        ),
        border: Border.all(color: const Color(0xFF2D4BB8), width: 1.3),
        boxShadow: const [BoxShadow(color: Color(0x442D6BFF), blurRadius: 10)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

/// One tappable row: [icon] title / subtitle [trailing].
class BlousabSettingsRow extends StatelessWidget {
  const BlousabSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor = const Color(0xFF2D9CFF),
    this.trailing,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            SizedBox(width: 38, child: Center(child: Icon(icon, color: iconColor, size: 32))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(title,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: Text(subtitle!,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Color(0xFFA3B5DE), fontSize: 12.5, height: 1.25)),
                  ),
                ],
              ]),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && showChevron && onTap != null)
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9C8FF), size: 28),
          ]),
        ),
      ),
    );
  }
}

/// Row with a switch.
class BlousabSwitchRow extends StatelessWidget {
  const BlousabSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.iconColor = const Color(0xFF2D9CFF),
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => BlousabSettingsRow(
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

/// Wide neon gradient button used for primary actions.
class BlousabPrimaryButton extends StatelessWidget {
  const BlousabPrimaryButton({super.key, required this.label, required this.icon, required this.onTap, this.busy = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: Opacity(
          opacity: onTap == null ? .5 : 1,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0xFF0B2E7A), Color(0xFF101B5C), Color(0xFF2B1470)]),
              border: Border.all(color: const Color(0xFF3FA2FF), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x773FA2FF), blurRadius: 12)],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              else
                Icon(icon, color: const Color(0xFFD59BFF), size: 24),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}
