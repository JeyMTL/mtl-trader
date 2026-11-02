import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/plans.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Plan cards and a hand-off to the hosted card checkout.
///
/// The checkout runs in the device browser: the processor collects the card, the
/// webhook applies the payment, and the account refreshes when the trader comes
/// back. Nothing card-related ever touches the app process.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.api});

  final JournalApi api;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<Map<String, dynamic>> _future;
  String? _busy;
  String? _error;

  /// Which cadence the buttons buy. A yearly price is its own entry in the
  /// provider's catalogue, so this only selects what is charged — the plan, its
  /// limits and its features are identical either way.
  bool _yearly = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.profile();
  }

  Future<void> _refresh() async {
    final next = widget.api.profile();
    setState(() {
      _future = next;
      _error = null;
    });
    try {
      await next;
    } catch (_) {
      // The error surface stays in the FutureBuilder.
    }
  }

  Future<void> _subscribe(String planId, String interval) async {
    if (_busy != null) return;
    setState(() {
      _busy = planId;
      _error = null;
    });

    try {
      final url = await widget.api.startCardSubscription(
        planId,
        interval: interval,
      );
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!opened) {
        setState(
          () => _error =
              'Could not open the payment page. Check your browser and try again.',
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finish the payment in your browser, then come back and refresh.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: Icon(Icons.refresh, size: 20, color: AppColors.muted),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }

          final profile = snapshot.data ?? const <String, dynamic>{};
          final tier =
              (asString(profile['subscription_tier']) ?? 'free').toLowerCase();
          final status = (asString(profile['subscription_status']) ?? 'trial')
              .toLowerCase();
          final periodEnd = asDate(profile['current_period_end']);
          final trialEnd = asDate(profile['trial_ends_at']);
          final maxTrades = asInt(profile['max_trades']);
          final active = status == 'active';
          final trial = status == 'trial';

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
              children: [
                _currentPlan(
                  tier: tier,
                  status: status,
                  maxTrades: maxTrades,
                  periodEnd: periodEnd,
                  trialEnd: trialEnd,
                  active: active,
                  trial: trial,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  FlatCard(
                    padding: const EdgeInsets.all(12),
                    borderColor: AppColors.danger.withAlpha(80),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 14,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SectionTitle(
                  title: 'Plans',
                  subtitle: _yearly
                      ? 'A yearly card subscription renews once a year. Cancel any time and keep access until the period ends.'
                      : 'A card subscription renews monthly. Cancel any time and keep access until the period ends.',
                ),
                const SizedBox(height: 8),
                _cadenceToggle(),
                const SizedBox(height: 10),
                for (final plan in mobilePlans) ...[
                  _planCard(
                    plan: plan,
                    current: active && tier == plan.id,
                    enabled: _busy == null,
                    busy: _busy == plan.id,
                  ),
                  const SizedBox(height: 10),
                ],
                FlatCard(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: AppColors.faint,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Checkout opens in your browser through our payment '
                          'provider. Your card is stored by them, never by this '
                          'app. PayPal and bank transfer remain one-time 30-day '
                          'options on the web.',
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 10.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Monthly or yearly. The toggle is hidden behind a plain Row rather than a
  /// segmented control because two options read faster than a dropdown, and the
  /// yearly label has to fit on one line on a phone.
  Widget _cadenceToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final yearly in const <bool>[false, true])
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _yearly = yearly),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: _yearly == yearly
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    yearly ? 'Annual · 2 months free' : 'Monthly',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _yearly == yearly ? AppColors.ink : AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _currentPlan({
    required String tier,
    required String status,
    required int maxTrades,
    required DateTime? periodEnd,
    required DateTime? trialEnd,
    required bool active,
    required bool trial,
  }) {
    final label = active
        ? (tier == 'pro'
            ? 'Pro'
            : tier == 'basic'
                ? 'Basic'
                : 'Paid')
        : trial
            ? 'Free trial'
            : 'Free';

    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Current plan',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Pill(
                text: label.toUpperCase(),
                tone: active
                    ? Tone.positive
                    : trial
                        ? Tone.neutral
                        : Tone.negative,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            active
                ? 'Active'
                : trial
                    ? 'Trial'
                    : status == 'cancelled'
                        ? 'Cancelled'
                        : 'Expired',
            style: tabular.copyWith(
              color: active || trial ? AppColors.success : AppColors.danger,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            maxTrades <= 0 ? 'Unlimited trades' : '$maxTrades trades / month',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
          if (trial && trialEnd != null) ...[
            const SizedBox(height: 2),
            Text(
              'Trial ends ${DateFormat('d MMM yyyy').format(trialEnd)}',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ],
          if (active && periodEnd != null) ...[
            const SizedBox(height: 2),
            Text(
              'Paid through ${DateFormat('d MMM yyyy').format(periodEnd)}',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planCard({
    required MobilePlan plan,
    required bool current,
    required bool enabled,
    required bool busy,
  }) {
    // A monthly subscriber still needs the yearly button: switching cadence is
    // the one purchase the server allows on the plan they already own, and it
    // stacks onto the days they have left. Re-buying the same month is the
    // mistake this disables.
    final canBuy = !current || _yearly;
    return FlatCard(
      borderColor:
          plan.popular ? AppColors.primary.withAlpha(90) : AppColors.border,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The name takes whatever is left and the price never moves: with a
          // fixed row, a doubled system text size threw a RenderFlex overflow
          // across the whole card. Now the name truncates instead.
          Row(
            children: [
              Expanded(
                // A Wrap, not a Row: at the largest system text size the badge
                // is wider than the space left beside the name, and a Row has
                // nowhere to put it — it overflowed by 55px on a 320pt phone.
                // Here it drops onto a second line instead.
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      plan.name,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (plan.popular)
                      const Pill(text: 'POPULAR', tone: Tone.neutral),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        money(
                          _yearly ? plan.annualPrice ?? plan.price : plan.price,
                        ),
                        style: tabular.copyWith(
                          color: AppColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _yearly ? '/yr' : '/mo',
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            plan.allowance,
            style: TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
          if (_yearly && plan.annualPrice != null) ...[
            const SizedBox(height: 2),
            Text(
              '${money(plan.annualPrice! / 12)}/mo · two months free',
              style: TextStyle(color: AppColors.success, fontSize: 10.5),
            ),
          ],
          const SizedBox(height: 10),
          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: 12,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      feature,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: !canBuy || !enabled
                ? null
                : () => _subscribe(plan.id, _yearly ? 'year' : 'month'),
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.ink,
                    ),
                  )
                : Text(
                    current
                        ? (_yearly ? 'Switch to annual' : 'Current plan')
                        : 'Subscribe with card',
                  ),
          ),
        ],
      ),
    );
  }
}
