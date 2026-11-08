import 'package:flutter/material.dart';

import '../brand.dart';

/// One round button, as Apple Notes draws back, done and compose: quiet in [BrandColors.card], or filled with the
/// accent for a page's one main action. [tooltip] is also the name a screen reader says.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.accent = false,
    this.size = 44});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: size * 0.5,
      constraints: BoxConstraints.tight(Size.square(size)),
      style: IconButton.styleFrom(backgroundColor: accent ? brand.accent : brand.card,
        foregroundColor: accent ? brand.onAccent : brand.ink, shape: const CircleBorder()),
      icon: Icon(icon),
    );
  }
}

/// Round buttons side by side in one quiet pill, as Apple Notes groups share and ⋯.
class ButtonPill extends StatelessWidget {
  const ButtonPill({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: brandOf(context).card, shape: const StadiumBorder()),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// A button inside a [ButtonPill]: its icon alone, on the pill's own fill.
class PillIconButton extends StatelessWidget {
  const PillIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 22,
    constraints: BoxConstraints.tight(const Size.square(44)),
    color: brandOf(context).ink,
    icon: Icon(icon),
  );
}
