import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';

// A fixed, clean cool set for the rim around the mark, matching the ice-blue
// artwork. The theme's primary stays brass (it has to work on buttons and text);
// at badge size the mark carries its own brighter metal.
const Color _rimLight = Color(0xFFE8F9FF);
const Color _rimBright = Color(0xFF7ED9FA);
const Color _rimDeep = Color(0xFF1E7FC0);

/// The store icon, generated from `assets/brand/app-icon.svg` by
/// `scripts/make-app-icons.mjs`. Declared in pubspec.yaml.
const String kBrandIconAsset = 'assets/brand/app_icon.png';

/// The MTL monogram — the ice-blue M on the brand's navy, with the equity
/// arrow — inside a cool rim with a slow luminous pulse, optionally with today's date
/// underneath. Used in the desk header and, larger, on login.
///
/// The artwork is the same file the launcher, the favicon and the store listing
/// use, so the icon a user taps is the mark they see inside.
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
    // Kept as a ratio of fontSize so every existing call site — the 21px header
    // mark and the 30px login mark — keeps the size it asked for.
    final scale = widget.fontSize / 21;
    final mark = 26 * scale;
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
                // A metallic rim: a bright cool outer shell around the artwork.
                Container(
                  padding: EdgeInsets.all(1.25 * scale),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9 * scale),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _rimLight,
                        _rimBright,
                        _rimDeep,
                        _rimBright,
                      ],
                      stops: [0, 0.35, 0.72, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _rimBright.withAlpha((60 + 55 * t).round()),
                        blurRadius: (9 + 9 * t) * scale,
                        spreadRadius: (0.4 + 1.1 * t) * scale,
                      ),
                      BoxShadow(
                        color: _rimLight.withAlpha((18 + 22 * t).round()),
                        blurRadius: 3 * scale,
                      ),
                    ],
                  ),
                  child: Transform.scale(
                    scale: 1 + t * 0.05,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7.75 * scale),
                      child: Image.asset(
                        kBrandIconAsset,
                        width: mark,
                        height: mark,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        // The wordmark beside it already carries the name, and
                        // the wrapping Semantics node has the label.
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
                if (widget.showDate) ...[
                  const SizedBox(height: 3),
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
