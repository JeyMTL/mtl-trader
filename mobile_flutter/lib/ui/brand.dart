import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';

// A fixed, clean gold set for the wordmark. The theme's primary is deliberately
// deeper (it has to work on buttons and text), but at badge size it reads as
// brown, so the mark carries its own brighter metal.
const Color _goldLight = Color(0xFFFFF1C9);
const Color _goldBright = Color(0xFFF3C766);
const Color _goldDeep = Color(0xFFC68C2B);

/// The MTL wordmark: a gold rim with a slow luminous pulse, optionally with
/// today's date underneath. Used in the desk header and, larger, on login.
class BrandMark extends StatefulWidget {
  const BrandMark({
    super.key,
    this.fontSize = 21,
    this.showDate = true,
    this.onTap,
  });

  final double fontSize;
  final bool showDate;
  final VoidCallback? onTap;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.fontSize / 21;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: widget.onTap != null,
      label: widget.onTap == null ? l10n.brandName : l10n.brandOpenPlans,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12 * scale),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            // A repeated pulse is exactly the kind of motion a reduced-motion
            // setting asks to stop, so the mark holds a mid glow instead.
            final t = MediaQuery.maybeDisableAnimationsOf(context) ?? false
                ? 0.5
                : _pulse.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A metallic rim: a bright gold outer shell around a solid
                // inner face. The old tinted border let the surface bleed
                // through, which is what made the gold look muddy.
                Container(
                  padding: EdgeInsets.all(1.25 * scale),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10 * scale),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _goldLight,
                        _goldBright,
                        _goldDeep,
                        _goldBright,
                      ],
                      stops: [0, 0.35, 0.72, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _goldBright.withAlpha((60 + 55 * t).round()),
                        blurRadius: (9 + 9 * t) * scale,
                        spreadRadius: (0.4 + 1.1 * t) * scale,
                      ),
                      BoxShadow(
                        color: _goldLight.withAlpha((18 + 22 * t).round()),
                        blurRadius: 3 * scale,
                      ),
                    ],
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 9.5 * scale,
                      vertical: 2.4 * scale,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.8 * scale),
                      color: AppColors.palette.isLight
                          ? const Color(0xFFFCFAF4)
                          : const Color(0xFF0B0D12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 1 + t * 0.05,
                          child: Text(
                            'MTL',
                            style: TextStyle(
                              color: AppColors.text,
                              fontFamily: 'Sora',
                              fontSize: widget.fontSize,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8 * scale + t * 1.4,
                              shadows: AppColors.palette.isLight
                                  ? null
                                  : [
                                      Shadow(
                                        color: _goldBright.withAlpha(
                                          (30 + 40 * t).round(),
                                        ),
                                        blurRadius: (6 + 8 * t) * scale,
                                      ),
                                    ],
                            ),
                          ),
                        ),
                        SizedBox(width: 7 * scale),
                        Container(
                          width: 5 * scale,
                          height: 5 * scale,
                          decoration: BoxDecoration(
                            color: _goldBright.withAlpha(
                              (170 + 85 * t).round(),
                            ),
                            shape: BoxShape.circle,
                            boxShadow: AppColors.palette.isLight
                                ? null
                                : [
                                    BoxShadow(
                                      color: _goldLight.withAlpha(90),
                                      blurRadius: 4 * scale,
                                    ),
                                  ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.showDate) ...[
                  const SizedBox(height: 2),
                  Text(
                    longDay(DateTime.now()),
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: kMinLabelSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
