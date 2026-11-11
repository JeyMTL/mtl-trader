import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/plans.dart';
import '../core/subscription.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../services/play_billing.dart';
import '../services/telemetry.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Plan cards and the purchase path the phone app uses.
///
/// The mobile app sells through Google Play, full stop: a Play-distributed app
/// may not send buyers to an external checkout (the old card/Paddle page) for
/// the same subscription. Play's sheet collects the payment, and the purchase
/// token is verified by the server before any plan changes. The web version is a
/// separate Next.js app and keeps its hosted card checkout.
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

  /// Play Billing, only alive in the Play build. Null until the catalogue has
  /// loaded, which is what keeps the buttons disabled until there is a real
  /// price to show.
  PlayBilling? _play;
  Map<String, ProductDetails> _playProducts = const <String, ProductDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _playPurchases;
  bool _restoring = false;

  /// Which cadence the buttons buy. A yearly price is its own entry in the
  /// provider's catalogue, so this only selects what is charged — the plan, its
  /// limits and its features are identical either way.
  bool _yearly = false;

  /// Scrolls the lapsed-account notice down to the plan cards.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = widget.api.profile();
    // The first step of the funnel that matters: someone opening the paywall is
    // the closest thing to intent we can observe before a payment exists.
    Telemetry.event('paywall_view', {'cadence': _yearly ? 'year' : 'month'});
    unawaited(_initPlay());
  }

  @override
  void dispose() {
    _playPurchases?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _showPlans() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
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

  // --------------------------------------------------------- Google Play

  /// Loads the Play catalogue and starts listening for purchases.
  ///
  /// Play is the app's only purchase path, so a device where the store is
  /// unavailable gets an explanation instead of a browser checkout.
  Future<void> _initPlay() async {
    final play = PlayBilling();
    late final Map<String, ProductDetails> products;
    try {
      products = await play.load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google Play is not available on this device.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _play = play;
      _playProducts = products;
    });
    _playPurchases = play.purchases.listen(_onPurchases);

    // A renewal, or a purchase made on another phone, is known only to Google.
    // Re-checking the stored token here keeps the plan in step without making
    // the trader hunt for "Restore purchases".
    try {
      await widget.api.syncGooglePlaySubscription();
      await _refresh();
    } catch (_) {
      // Offline, or nothing bought yet: the card above still shows what the
      // server already knows.
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyPlayPurchase(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(
            () => _error = purchase.error?.message ??
                'Google Play could not complete the purchase. Nothing was charged.',
          );
        }
      }
      // Play re-delivers an unfinished purchase, so it is cleared even when the
      // server check failed: the token is stored on the account either way.
      await _play?.finish(purchase);
    }
    if (mounted) setState(() => _busy = null);
  }

  /// Hands the purchase token to the server, which asks Google what it is worth.
  /// The app never decides for itself that a payment happened.
  Future<void> _verifyPlayPurchase(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData.isNotEmpty
        ? purchase.verificationData.serverVerificationData
        : (purchase.purchaseID ?? '');
    if (token.isEmpty) {
      if (mounted) {
        setState(() => _error = 'Google Play did not return a purchase token.');
      }
      return;
    }

    try {
      final result = await widget.api.syncGooglePlaySubscription(
        purchaseToken: token,
        productId: purchase.productID,
      );
      final active = asString(result['status']) == 'active';
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'Payment confirmed. Your plan is active.'
                : 'Google Play is still processing the payment. Refresh in a minute.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _buyWithPlay(ProductDetails product) async {
    final entry = playCatalog[product.id];
    Telemetry.event('checkout_started', {
      'plan': entry?.planId ?? product.id,
      'interval': entry?.interval ?? 'month',
      'provider': 'google_play',
    });
    setState(() {
      _busy = entry?.planId ?? product.id;
      _error = null;
    });
    try {
      await _play!.buy(product);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _busy = null;
      });
    }
    // Otherwise Play reports back on the purchase stream and that clears _busy.
  }

  Future<void> _restorePurchases() async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      await _play?.restore();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
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
          final info = SubscriptionInfo.fromProfile(profile);
          final tier = info.tier;
          final active = info.state == SubscriptionState.active;

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
              children: [
                _currentPlan(info),
                if (info.ended) ...[
                  const SizedBox(height: 10),
                  _endedNotice(info),
                ],
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
                      ? 'Billed by Google Play once a year. Cancel any time in Play Store → Payments and subscriptions, and keep access until the period ends.'
                      : 'Billed by Google Play monthly. Cancel any time in Play Store → Payments and subscriptions, and keep access until the period ends.',
                ),
                // Play sells each cadence as its own base plan, so the toggle
                // only chooses what is charged.
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
                Center(
                  child: TextButton(
                    onPressed: _play == null || _restoring
                        ? null
                        : _restorePurchases,
                    child: Text(
                      _restoring
                          ? 'Checking Google Play…'
                          : 'Restore purchases',
                    ),
                  ),
                ),
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
                          'Payment is handled by Google Play, which stores '
                          'your card and renews the plan. Cancel any time in '
                          'Play Store → Payments and subscriptions; access '
                          'runs to the end of the period you paid for.',
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
                      color:
                          _yearly == yearly ? AppColors.ink : AppColors.muted,
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

  Widget _currentPlan(SubscriptionInfo info) {
    final active = info.state == SubscriptionState.active;
    final trial = info.state == SubscriptionState.trial;

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
                text: info.planLabel.toUpperCase(),
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
            info.statusLabel,
            style: tabular.copyWith(
              color: info.hasAccess ? AppColors.success : AppColors.danger,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info.maxTrades <= 0
                ? 'Unlimited trades'
                : '${info.maxTrades} trades / month',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
          if (trial && info.trialEndsAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Trial ends ${DateFormat('d MMM yyyy').format(info.trialEndsAt!)}',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ],
          if (active && info.periodEndsAt != null) ...[
            const SizedBox(height: 2),
            Text(
              info.cancelAtPeriodEnd
                  ? 'Renewal stopped · access until '
                      '${DateFormat('d MMM yyyy').format(info.periodEndsAt!)}'
                  : 'Paid through '
                      '${DateFormat('d MMM yyyy').format(info.periodEndsAt!)}',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  /// The one message a lapsed account must not miss: access is over and renewing
  /// is the only way back in. It sits directly under the plan card and owns the
  /// only button that scrolls to the plans.
  Widget _endedNotice(SubscriptionInfo info) {
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      borderColor: AppColors.danger.withAlpha(110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.endedTitle,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            info.endedBody,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showPlans,
              child: Text(info.callToAction),
            ),
          ),
        ],
      ),
    );
  }

  /// The Google Play buy control.
  ///
  /// Play owns the transaction: the sheet, the card, the receipt and the
  /// renewal. The app passes a product id and, once Play reports back, hands the
  /// purchase token to the server — which is the only party that decides, after
  /// asking Google, whether a plan was paid for.
  Widget _googlePlayButton({
    required bool current,
    required bool enabled,
    required bool busy,
    required ProductDetails? product,
  }) {
    final sellable = product;
    final canBuy = canBuyWithPlay(
      current: current,
      yearly: _yearly,
      enabled: enabled,
      hasProduct: sellable != null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: canBuy && sellable != null
              ? () => _buyWithPlay(sellable)
              : null,
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
                      : 'Subscribe with Google Play',
                ),
        ),
        // Play returns nothing for a product that is not on sale in the buyer's
        // country or has not been activated in the console. Saying so beats a
        // button that looks tappable and does nothing.
        if (product == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _play == null
                  ? 'Google Play is not available on this device.'
                  : 'This plan is not on sale for your account yet.',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ),
      ],
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
    // Play owns the price display. The store price can differ from our list
    // price by country, tax and promotions, and showing ours next to the amount
    // Google actually charges is the kind of mismatch that turns into a support
    // ticket and a refund request.
    final playProduct =
        _playProducts[playProductIdFor(plan.id, _yearly ? 'year' : 'month')];
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
                        playProduct?.price ??
                            money(
                              _yearly
                                  ? plan.annualPrice ?? plan.price
                                  : plan.price,
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
          // Play is the phone app's only purchase path: a Play-distributed app
          // may not send buyers to an external checkout for this subscription.
          _googlePlayButton(
            current: current,
            enabled: enabled,
            busy: busy,
            product: playProduct,
          ),
        ],
      ),
    );
  }
}
