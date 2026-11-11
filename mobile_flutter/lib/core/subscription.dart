import '../models/models.dart';
import 'plans.dart';

/// Where an account's plan access actually stands, resolved against the clock.
///
/// Mirrors `subscriptionState()` in `src/lib/subscription.ts`: the stored status
/// is not enough, because a period can end (or a trial run out) before the daily
/// expiry job rewrites the row. A lapsed account must read as ended everywhere in
/// the app, or the trader keeps seeing "Active" next to a date in the past.
enum SubscriptionState { trial, active, cancelled, expired }

/// One account's plan, its access, and the wording to show about it.
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.state,
    required this.status,
    required this.tier,
    required this.maxTrades,
    this.trialEndsAt,
    this.periodEndsAt,
    this.cancelAtPeriodEnd = false,
  });

  final SubscriptionState state;

  /// The stored status (`trial`, `active`, `cancelled`, `expired`). Kept so the
  /// wording can tell a trial that ran out from a paid plan that lapsed.
  final String status;

  /// Stored tier id (`free`, `basic`, `pro`); unknown ids read as `free`.
  final String tier;

  /// `-1` means unlimited.
  final int maxTrades;

  final DateTime? trialEndsAt;
  final DateTime? periodEndsAt;

  /// A paid period the trader has already stopped from renewing. Access runs to
  /// [periodEndsAt]; after that the account expires.
  final bool cancelAtPeriodEnd;

  static SubscriptionInfo fromProfile(
    Map<String, dynamic> profile, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final status = (asString(profile['subscription_status']) ?? 'expired')
        .toLowerCase();
    final tier = (asString(profile['subscription_tier']) ?? 'free').toLowerCase();
    final trialEnd = asDate(profile['trial_ends_at']);
    final periodEnd = asDate(profile['current_period_end']);
    final maxTrades = asInt(profile['max_trades']);
    final cancelAtPeriodEnd = asBool(profile['cancel_at_period_end']);

    final state = _resolve(
      status: status,
      tier: tier,
      trialEndsAt: trialEnd,
      periodEndsAt: periodEnd,
      now: clock,
    );

    return SubscriptionInfo(
      state: state,
      status: status,
      tier: tier,
      maxTrades: maxTrades,
      trialEndsAt: trialEnd,
      periodEndsAt: periodEnd,
      cancelAtPeriodEnd: cancelAtPeriodEnd,
    );
  }

  static SubscriptionState _resolve({
    required String status,
    required String tier,
    required DateTime? trialEndsAt,
    required DateTime? periodEndsAt,
    required DateTime now,
  }) {
    final paidTier = mobilePlans.any((plan) => plan.id == tier && plan.price > 0);

    if (status == 'trial' &&
        trialEndsAt != null &&
        trialEndsAt.isAfter(now)) {
      return SubscriptionState.trial;
    }
    if (status == 'active' &&
        paidTier &&
        periodEndsAt != null &&
        periodEndsAt.isAfter(now)) {
      return SubscriptionState.active;
    }
    if (status == 'cancelled') return SubscriptionState.cancelled;
    return SubscriptionState.expired;
  }

  /// True while the journal is usable: a running trial or a paid period.
  bool get hasAccess =>
      state == SubscriptionState.trial || state == SubscriptionState.active;

  /// True when the plan is over and the only way back in is a purchase.
  bool get ended => !hasAccess;

  /// Whether a paid plan was held before it lapsed (as opposed to a trial that
  /// never converted). Changes the wording, not the offer.
  bool get lapsedPaidPlan => ended && status != 'trial' && _isPaidTier(tier);

  static bool _isPaidTier(String tier) =>
      mobilePlans.any((plan) => plan.id == tier && plan.price > 0);

  /// `Basic`, `Pro`, `Free trial` or `Free` — the label for a pill.
  String get planLabel {
    switch (state) {
      case SubscriptionState.trial:
        return 'Free trial';
      case SubscriptionState.active:
        return tier == 'pro'
            ? 'Pro'
            : tier == 'basic'
                ? 'Basic'
                : 'Paid';
      case SubscriptionState.cancelled:
      case SubscriptionState.expired:
        return 'Free';
    }
  }

  /// The one-line status under a plan name.
  String get statusLabel {
    switch (state) {
      case SubscriptionState.trial:
        return 'Trial';
      case SubscriptionState.active:
        return 'Active';
      case SubscriptionState.cancelled:
        return 'Cancelled — subscription ended';
      case SubscriptionState.expired:
        return 'Subscription ended';
    }
  }

  /// The heading a lapsed account sees. The point is not to be subtle: access
  /// has stopped, and renewing is the only way to keep using the journal.
  String get endedTitle {
    if (state == SubscriptionState.cancelled) {
      return 'Your subscription was cancelled';
    }
    if (lapsedPaidPlan) return 'Your subscription has ended';
    if (status == 'trial') return 'Your free trial has ended';
    return 'Your subscription has ended';
  }

  String get endedBody {
    if (lapsedPaidPlan) {
      return 'Buy a subscription to keep recording trades, viewing analytics and '
          'opening the chart. Your journal is safe — nothing was deleted.';
    }
    return 'Buy a subscription to keep recording trades, viewing analytics and '
        'opening the chart.';
  }

  /// The label on the recovery button.
  String get callToAction => lapsedPaidPlan || state == SubscriptionState.cancelled
      ? 'Buy a subscription'
      : 'Subscribe now';

  /// Remaining days in the current paid period, or 0.
  int daysLeftInPeriod({DateTime? now}) {
    if (state != SubscriptionState.active || periodEndsAt == null) return 0;
    final clock = now ?? DateTime.now();
    final ms = periodEndsAt!.difference(clock).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / Duration.millisecondsPerDay).ceil();
  }
}
