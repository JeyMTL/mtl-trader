import 'dart:async';

import 'package:flutter/material.dart';

import '../core/subscription.dart';
import '../l10n/gen/app_localizations.dart';
import 'brand.dart';
import 'theme.dart';

/// The plan entry point in the desk header.
///
/// TradingView's shape: a small pill, a gradient rim, the mark inside it and the
/// words beside it. The mark is what makes the pill read as the app's own offer
/// rather than a button bolted onto the bar, and it is why nothing else sits in
/// the middle of the header.
///
/// The words are the account's own state, not a constant: "Pro" while a paid
/// plan runs, "Trial · 12d" while the trial does, and "Upgrade" only when there
/// is nothing to manage. A pill that says Upgrade to someone who already paid is
/// an advert aimed at a customer.
class UpgradePill extends StatefulWidget {
  const UpgradePill({super.key, required this.onTap, this.plan});

  final VoidCallback onTap;

  /// The account's plan, or null until the profile has loaded — in which case
  /// the pill keeps the neutral "Upgrade" rather than guessing.
  final SubscriptionInfo? plan;

  /// The word that belongs in the pill for this account.
  ///
  /// [now] exists so the trial countdown can be checked against a fixed clock;
  /// on screen it is the device's own time.
  String label(AppLocalizations l10n, {DateTime? now}) {
    final info = plan;
    if (info == null) return l10n.upgrade;
    switch (info.state) {
      case SubscriptionState.active:
        return info.planLabel;
      case SubscriptionState.trial:
        final days = info.daysLeftInTrial(now: now);
        return days > 0 ? l10n.planTrialDays(days) : l10n.upgrade;
      case SubscriptionState.cancelled:
      case SubscriptionState.expired:
        return l10n.upgrade;
    }
  }

  @override
  State<UpgradePill> createState() => _UpgradePillState();
}

class _UpgradePillState extends State<UpgradePill> {
  /// The trial ends at a fixed instant, so the label is recomputed from the
  /// clock even while nobody touches the app. A timer is what makes a pill
  /// that said "Trial · 7d" yesterday say "Trial · 6d" today without a reload.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.plan?.state == SubscriptionState.trial) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// The far end of the rim. The near end is the theme's own primary, so the
  /// gradient still belongs to the palette in every appearance.
  static const Color _rimEnd = Color(0xFF9D5BFF);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(999);
    final label = widget.label(l10n);
    return Semantics(
      button: true,
      label: '$label — ${l10n.accountViewPlans}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.primary, _rimEnd],
              ),
            ),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: radius,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The same artwork as the launcher and the login mark, at the
                  // size a 32px pill can carry without turning into a badge.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.asset(
                      kBrandIconAsset,
                      width: 18,
                      height: 18,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      // A long translation at a large text scale has to give
                      // somewhere other than the fixed 32px height: it shortens
                      // instead of clipping.
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.15,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
