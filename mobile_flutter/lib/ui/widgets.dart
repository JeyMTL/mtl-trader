import 'package:flutter/material.dart';

import 'theme.dart';

/// Every price, balance and percentage uses the mono face, so digits line up
/// in columns instead of shifting as values change.
const TextStyle tabular = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontFeatures: [FontFeature.tabularFigures()],
  letterSpacing: -0.2,
  height: 1.15,
);

class FlatCard extends StatefulWidget {
  const FlatCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  State<FlatCard> createState() => _FlatCardState();
}

class _FlatCardState extends State<FlatCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          // A soft drop shadow lifts the card off the near-black background;
          // the border alone made the surface read flat.
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withAlpha(AppColors.palette.isLight ? 14 : 70),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: widget.color ?? AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: widget.borderColor ?? AppColors.border,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: widget.onTap == null
                ? null
                : (value) => setState(() => _pressed = value),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// A titled block of related settings, drawn as a card.
///
/// The chart's bottom sheets group their options into these, so a sheet reads as
/// a handful of labelled decisions instead of one column of controls. `trailing`
/// is the current value of the group, shown beside the label so the state is
/// legible without opening anything.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.foot,
    this.tone = Tone.neutral,
    this.icon,
    this.semanticValue,
  });

  final String label;
  final String value;
  final String? foot;
  final Tone tone;
  final IconData? icon;

  /// Spoken form of the number when it has a meaning colour and a sign cannot
  /// carry, e.g. "Profit of $1,204.10" for an average trade.
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    return FlatCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: kMinLabelSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (icon != null) Icon(icon, size: 15, color: AppColors.faint),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Semantics(
              label: semanticValue ?? '$label $value',
              excludeSemantics: true,
              child: Text(
                value,
                style: tabular.copyWith(
                  color: toneColor(tone),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          if (foot != null) ...[
            const SizedBox(height: 3),
            Text(
              foot!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.faint,
                fontSize: kMinLabelSize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.tone = Tone.neutral,
    this.icon,
  });

  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          // Flexible so a long label (“EN DRAWDOWN” at a 2x text scale)
          // ellipsises instead of pushing its row past the card edge.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: kMinLabelSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            width: 128,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withAlpha(38),
                        AppColors.primary.withAlpha(0),
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  size: const Size(112, 56),
                  painter: _EmptyChartPainter(
                    line: AppColors.primary.withAlpha(150),
                    grid: AppColors.border,
                    fill: AppColors.primary.withAlpha(26),
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(icon, size: 13, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.faint,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// A tiny dashed chart behind the empty-state icon: enough to suggest the
/// screen will fill with data without needing an illustration asset.
class _EmptyChartPainter extends CustomPainter {
  const _EmptyChartPainter({
    required this.line,
    required this.grid,
    required this.fill,
  });

  final Color line;
  final Color grid;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.7;
    for (var i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = <Offset>[
      Offset(size.width * 0.04, size.height * 0.78),
      Offset(size.width * 0.3, size.height * 0.55),
      Offset(size.width * 0.55, size.height * 0.66),
      Offset(size.width * 0.96, size.height * 0.18),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width * 0.96, size.height)
      ..lineTo(size.width * 0.04, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill, fill.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.2, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(covariant _EmptyChartPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.grid != grid;
}

class LabelValue extends StatelessWidget {
  const LabelValue({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
          // The value and whatever trails it share one flexible slot, so a
          // small badge or a long amount cannot overrun the row.
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: tabular.copyWith(
                      color: valueColor ?? AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  Flexible(child: trailing!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListDivider extends StatelessWidget {
  const ListDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.border);
  }
}
