import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/subscription.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations_en.dart';
import 'package:mtl_trader_mobile/ui/upgrade_pill.dart';

void main() {
  final now = DateTime(2026, 11, 11, 12);

  Map<String, dynamic> profile({
    String? status,
    String? tier,
    DateTime? trialEnds,
    DateTime? periodEnds,
    bool cancelAtPeriodEnd = false,
  }) =>
      <String, dynamic>{
        'subscription_status': status,
        'subscription_tier': tier,
        'trial_ends_at': trialEnds?.toIso8601String(),
        'current_period_end': periodEnds?.toIso8601String(),
        'cancel_at_period_end': cancelAtPeriodEnd,
        'max_trades': -1,
      };

  test('an active paid period reads active', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'active',
        tier: 'pro',
        periodEnds: now.add(const Duration(days: 9)),
      ),
      now: now,
    );
    expect(info.state, SubscriptionState.active);
    expect(info.hasAccess, isTrue);
    expect(info.planLabel, 'Pro');
    expect(info.daysLeftInPeriod(now: now), 9);
  });

  test('a period that has passed reads ended even while the row says active', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'active',
        tier: 'pro',
        periodEnds: now.subtract(const Duration(days: 1)),
      ),
      now: now,
    );
    expect(info.state, SubscriptionState.expired);
    expect(info.ended, isTrue);
    expect(info.endedTitle, 'Your subscription has ended');
    expect(info.callToAction, 'Buy a subscription');
  });

  test('a failed renewal without a period end does not act like a lifetime plan', () {
    final info = SubscriptionInfo.fromProfile(
      profile(status: 'active', tier: 'basic'),
      now: now,
    );
    expect(info.state, SubscriptionState.expired);
  });

  test('a trial that has run out reads ended, with trial wording', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'trial',
        tier: 'free',
        trialEnds: now.subtract(const Duration(hours: 2)),
      ),
      now: now,
    );
    expect(info.state, SubscriptionState.expired);
    expect(info.endedTitle, 'Your free trial has ended');
    expect(info.callToAction, 'Subscribe now');
  });

  test('a running trial counts as access', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'trial',
        tier: 'free',
        trialEnds: now.add(const Duration(days: 3)),
      ),
      now: now,
    );
    expect(info.state, SubscriptionState.trial);
    expect(info.hasAccess, isTrue);
    expect(info.planLabel, 'Free trial');
  });

  test('a cancelled subscription reads ended even if the row still carries a tier', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'cancelled',
        tier: 'pro',
        periodEnds: now.add(const Duration(days: 4)),
      ),
      now: now,
    );
    expect(info.state, SubscriptionState.cancelled);
    expect(info.ended, isTrue);
    expect(info.endedTitle, 'Your subscription was cancelled');
    expect(info.planLabel, 'Free');
    expect(info.statusLabel, 'Cancelled — subscription ended');
  });

  test('a stopped renewal keeps access until the paid period ends', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'active',
        tier: 'basic',
        periodEnds: now.add(const Duration(days: 5)),
        cancelAtPeriodEnd: true,
      ),
      now: now,
    );
    expect(info.state, SubscriptionState.active);
    expect(info.hasAccess, isTrue);
    expect(info.cancelAtPeriodEnd, isTrue);
  });

  test('trial days round up, so a trial with hours left still reads 1d', () {
    final info = SubscriptionInfo.fromProfile(
      profile(status: 'trial', trialEnds: now.add(const Duration(hours: 11))),
      now: now,
    );
    expect(info.state, SubscriptionState.trial);
    expect(info.daysLeftInTrial(now: now), 1);
  });

  test('a paid plan has no trial days left to show', () {
    final info = SubscriptionInfo.fromProfile(
      profile(
        status: 'active',
        tier: 'pro',
        periodEnds: now.add(const Duration(days: 9)),
      ),
      now: now,
    );
    expect(info.daysLeftInTrial(now: now), 0);
  });

  group('the desk pill names the plan the account is on', () {
    final l10n = AppLocalizationsEn();

    test('a paid plan shows the tier and not an offer', () {
      final info = SubscriptionInfo.fromProfile(
        profile(
          status: 'active',
          tier: 'pro',
          periodEnds: now.add(const Duration(days: 9)),
        ),
        now: now,
      );
      expect(UpgradePill(onTap: () {}, plan: info).label(l10n), 'Pro');
    });

    test('a running trial shows the days left', () {
      final info = SubscriptionInfo.fromProfile(
        profile(status: 'trial', trialEnds: now.add(const Duration(days: 12))),
        now: now,
      );
      expect(
        UpgradePill(onTap: () {}, plan: info).label(l10n, now: now),
        'Trial · 12d',
      );
    });

    test('an ended plan offers the upgrade again', () {
      final info = SubscriptionInfo.fromProfile(
        profile(
          status: 'active',
          tier: 'pro',
          periodEnds: now.subtract(const Duration(days: 1)),
        ),
        now: now,
      );
      expect(UpgradePill(onTap: () {}, plan: info).label(l10n), 'Upgrade');
    });

    test('before the profile loads it keeps the neutral word', () {
      expect(UpgradePill(onTap: () {}).label(l10n), 'Upgrade');
    });
  });
}
