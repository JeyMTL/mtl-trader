import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';

/// Profit and loss must not be carried by colour alone: red/green is invisible
/// to roughly one in twelve men, and on a greyscale screenshot it is invisible
/// to everyone. Every amount gets an arrow, a sign and a screen-reader label.
class PnlText extends StatelessWidget {
  const PnlText({
    super.key,
    required this.value,
    this.style,
    this.glyph = true,
    this.align = TextAlign.right,
  });

  final num value;
  final TextStyle? style;

  /// The ▲/▼ marker. Off in places that already carry an arrow of their own.
  final bool glyph;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final positive = value > 0;
    final color = value == 0
        ? AppColors.muted
        : positive
            ? AppColors.success
            : AppColors.danger;
    final spoken = value == 0
        ? l10n.a11yBreakEven(money(value))
        : positive
            ? l10n.a11yProfit(money(value))
            : l10n.a11yLoss(money(value.abs()));

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(
        glyph
            ? '${positive ? '▲' : value == 0 ? '■' : '▼'} ${signedMoney(value)}'
            : signedMoney(value),
        textAlign: align,
        maxLines: 1,
        // The spoken label carries the full amount, so a clipped display is
        // better than a row that overflows at a large text size.
        overflow: TextOverflow.ellipsis,
        style: (style ?? const TextStyle()).copyWith(color: color),
      ),
    );
  }
}

/// Screen-reader label for a signed amount, without drawing anything.
String pnlLabel(BuildContext context, num value) {
  final l10n = AppLocalizations.of(context);
  if (value == 0) return l10n.a11yBreakEven(money(value));
  return value > 0
      ? l10n.a11yProfit(money(value))
      : l10n.a11yLoss(money(value.abs()));
}

/// An icon plus a count that also says what it counts. A bare "3" after a
/// picture icon is read aloud as "three", which tells a screen-reader user
/// nothing about the row it sits in.
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.primary),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: kMinLabelSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a painted chart so a screen reader gets one useful sentence instead of
/// a pile of unlabelled pixels.
class ChartSemantics extends StatelessWidget {
  const ChartSemantics({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: child),
    );
  }
}
