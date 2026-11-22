import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/alerts.dart';
import '../services/daily_stop_bus.dart';
import '../l10n/gen/app_localizations.dart';
import '../services/journal_api.dart';
import '../services/mt5_freezer.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The gate wraps the Navigator (see `MaterialApp.builder`), so its own context
/// has no Navigator above it and `showDialog` would throw there. The app hands
/// this key to `MaterialApp` so the gate can still open a dialog on the
/// navigator it is sitting on top of.
final GlobalKey<NavigatorState> dayGateNavigatorKey =
    GlobalKey<NavigatorState>();

/// Shows [builder] on the app's root navigator, from above it.
Future<T?> showGateDialog<T>(WidgetBuilder builder) {
  final context = dayGateNavigatorKey.currentContext;
  if (context == null) return Future<T?>.value();
  return showDialog<T>(context: context, builder: builder);
}

/// Wraps the app in the daily stop.
///
/// A soft lock leaves the journal usable and freezes MT5 on the phone through
/// the accessibility service; a notice offers the recorded reset. A hard lock
/// freezes every screen behind one wall while the desktop EA blocks trading, and
/// has no release of its own: it clears when the trading day rolls over, which
/// is the whole reason for choosing it over soft.
///
/// The gate re-reads on resume as well as on a timer: coming back to the app
/// the next morning must not still show yesterday's wall.
class DayLockGate extends StatefulWidget {
  const DayLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<DayLockGate> createState() => _DayLockGateState();
}

class _DayLockGateState extends State<DayLockGate> with WidgetsBindingObserver {
  final JournalApi _api = JournalApi();
  Map<String, dynamic>? _data;
  Timer? _timer;
  Timer? _debounce;
  StreamSubscription<AuthState>? _auth;
  RealtimeChannel? _tradeChannel;
  RealtimeChannel? _settingsChannel;
  String? _watchedUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DailyStopBus.version.addListener(_onSettingsChanged);
    _refresh();
    unawaited(_startWatch());
    // The gate lives above the Navigator, so it outlives the login screen:
    // signing in has to trigger a read rather than wait for the next tick.
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.tokenRefreshed ||
          state.event == AuthChangeEvent.initialSession) {
        unawaited(_startWatch());
        _refresh();
      } else if (state.event == AuthChangeEvent.signedOut) {
        _watchedUser = null;
        final tradeChannel = _tradeChannel;
        final settingsChannel = _settingsChannel;
        if (tradeChannel != null) unawaited(tradeChannel.unsubscribe());
        if (settingsChannel != null) unawaited(settingsChannel.unsubscribe());
        _tradeChannel = null;
        _settingsChannel = null;
        if (mounted) setState(() => _data = null);
        Mt5Freezer.sync(active: false);
      }
    });
    // A trade lands in the journal in under a second; the listeners below are
    // the fast path, and this two-second read is the fallback for a project
    // without the tables in the realtime publication.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    _auth?.cancel();
    final tradeChannel = _tradeChannel;
    final settingsChannel = _settingsChannel;
    if (tradeChannel != null) unawaited(tradeChannel.unsubscribe());
    if (settingsChannel != null) unawaited(settingsChannel.unsubscribe());
    DailyStopBus.version.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Trade inserts and playbook edits are the only two things that can change
  /// the answer. Realtime delivers either in a few hundred milliseconds; the
  /// soft freeze follows on the same refresh, so MT5 is covered right after a
  /// close that breaches the day.
  Future<void> _startWatch() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid == _watchedUser) return;
    final oldTrade = _tradeChannel;
    final oldSettings = _settingsChannel;
    if (oldTrade != null) unawaited(oldTrade.unsubscribe());
    if (oldSettings != null) unawaited(oldSettings.unsubscribe());
    _watchedUser = uid;
    // Separate channels: a table that is not in the realtime publication makes
    // its own channel fail, and it must not take the other one down with it.
    _tradeChannel = Supabase.instance.client
        .channel('day-lock-trades-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trades',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
    _settingsChannel = Supabase.instance.client
        .channel('day-lock-settings-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'playbooks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onSettingsChanged() {
    _refresh();
  }

  /// The day the trader was last told about, so a stop that stays on for the
  /// rest of the session produces one notification rather than one per poll.
  String? _notifiedDay;

  Future<void> _refresh() async {
    try {
      final data = await _api.dayState();
      if (!mounted) return;
      setState(() => _data = data);
      await _syncFreezer(data);
      await _announceStop(data);
    } catch (_) {
      // A failed read must not lock someone out; the last good state stands.
    }
  }

  /// Puts the daily stop on the phone's lock screen the moment it engages.
  ///
  /// Once per day: the gate polls every two seconds and the stop stays on until
  /// the day rolls over. If the trader records the override the lock goes quiet
  /// and this is allowed to speak again, which is what re-arming means here too.
  Future<void> _announceStop(Map<String, dynamic> data) async {
    final lock = _asMap(data['lock']);
    final state = _asMap(data['state']);
    if (lock['active'] != true || state['breached'] != true) {
      _notifiedDay = null;
      return;
    }
    final day = _asMap(data['day']);
    final key = day['key'] is String
        ? day['key'] as String
        : DateTime.now().toIso8601String().substring(0, 10);
    if (_notifiedDay == key) return;
    _notifiedDay = key;
    final limit = state['lossLimit'] is num
        ? (state['lossLimit'] as num).toDouble()
        : 0.0;
    final used =
        state['lossUsed'] is num ? (state['lossUsed'] as num).toDouble() : 0.0;
    await Alerts.instance.dailyStopHit(
      lossUsed: used,
      lossLimit: limit,
      dayKey: key,
    );
  }

  /// Carries the soft lock to Android, where the accessibility service covers
  /// MT5. Hard mode leaves the phone alone: its enforcement is the desktop EA.
  Future<void> _syncFreezer(Map<String, dynamic> data) async {
    final lock = _asMap(data['lock']);
    final state = _asMap(data['state']);
    final soft = lock['mode'] == 'soft' &&
        lock['active'] == true &&
        state['breached'] == true;
    if (!soft) {
      await Mt5Freezer.sync(active: false);
      return;
    }
    final day = _asMap(data['day']);
    final end =
        day['end'] is String ? DateTime.tryParse(day['end'] as String) : null;
    final limit = state['lossLimit'] is num
        ? (state['lossLimit'] as num).toDouble()
        : 0.0;
    final used =
        state['lossUsed'] is num ? (state['lossUsed'] as num).toDouble() : 0.0;
    final l10n = AppLocalizations.of(context);
    final message = limit > 0
        ? l10n.lockBudgetMessage(
            '\$${used.toStringAsFixed(2)}',
            '\$${limit.toStringAsFixed(2)}',
          )
        : l10n.lockStopReached;
    await Mt5Freezer.sync(active: true, until: end, message: message);
  }

  bool get _active {
    final data = _data;
    if (data == null || data['missing'] == true) return false;
    final lock = data['lock'];
    if (lock is! Map) return false;
    if (lock['active'] != true) return false;
    final state = data['state'];
    return state is Map && state['breached'] == true;
  }

  bool get _soft {
    final lock = _data?['lock'];
    return lock is Map && lock['mode'] == 'soft';
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;

    // Soft freezes MT5, not the journal. A bottom notice keeps the override
    // reachable without covering the screen the trader can still use.
    if (_soft) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _SoftLockBanner(
                data: _data!,
                api: _api,
                onUnfrozen: () {
                  setState(() => _data = null);
                  _refresh();
                },
              ),
            ),
          ),
        ],
      );
    }

    return DayLockScreen(
      data: _data!,
      api: _api,
      onUnfrozen: () {
        setState(() => _data = null);
        _refresh();
      },
    );
  }
}

class DayLockScreen extends StatefulWidget {
  const DayLockScreen({
    super.key,
    required this.data,
    required this.api,
    required this.onUnfrozen,
  });

  final Map<String, dynamic> data;
  final JournalApi api;
  final VoidCallback onUnfrozen;

  @override
  State<DayLockScreen> createState() => _DayLockScreenState();
}

class _DayLockScreenState extends State<DayLockScreen> {
  /// Read through the State's own context: the wall is built in helper methods
  /// as well as in `build`.
  AppLocalizations get _l10n => AppLocalizations.of(context);
  late Timer _ticker;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Map<String, dynamic> get _state => _asMap(widget.data['state']);
  Map<String, dynamic> get _lock => _asMap(widget.data['lock']);
  Map<String, dynamic> get _day => _asMap(widget.data['day']);

  bool get _hard => _lock['mode'] == 'hard';

  double _num(Object? value) => value is num ? value.toDouble() : 0;

  String _money(double value) {
    final sign = value < 0 ? '-' : '';
    final abs = value.abs();
    final fixed = abs.toStringAsFixed(abs >= 1000 ? 0 : 2);
    return '$sign\$$fixed';
  }

  DateTime? get _end {
    final raw = _day['end'];
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  String _countdown(DateTime end) {
    final ms = end.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 'resetting now';
    final minutes = (ms / 60000).ceil();
    if (minutes < 60) return 'in $minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'in $hours h' : 'in $hours h $rest min';
  }

  String get _clock {
    final end = _end;
    if (end == null) return '';
    final local = end.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _unfreeze() async {
    final reason = await showGateDialog<String>(
      (context) => const _UnfreezeDialog(),
    );
    if (reason == null || reason.trim().length < 10 || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.api.overrideDayStop(reason.trim());
      if (mounted) widget.onUnfrozen();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final lossLimit = _num(state['lossLimit']);
    final lossUsed = _num(state['lossUsed']);
    final maxTrades = _num(state['maxTrades']).toInt();
    final tradesCount = _num(state['tradesCount']).toInt();
    final limitReached = lossLimit > 0 && lossUsed >= lossLimit;
    final end = _end;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: (_hard ? AppColors.danger : AppColors.primary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: (_hard ? AppColors.danger : AppColors.primary)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(
                        _hard ? Icons.gpp_maybe_outlined : Icons.lock_outline,
                        size: 30,
                        color: _hard ? AppColors.danger : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _hard
                        ? AppLocalizations.of(context).lockHardBadge
                        : AppLocalizations.of(context).lockSoftBadge,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context).lockDayOver,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    limitReached
                        ? AppLocalizations.of(context)
                            .lockLossBody(_money(lossUsed), _money(lossLimit))
                        : AppLocalizations.of(context)
                            .lockCapBody('$tradesCount', '$maxTrades'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _Stat(
                          label: _l10n.lockRealised,
                          value: _money(_num(state['realizedPnl']))),
                      const SizedBox(width: 8),
                      _Stat(label: _l10n.lockEntries, value: '$tradesCount'),
                      const SizedBox(width: 8),
                      _Stat(
                        label: _l10n.lockAfterStop,
                        value: '${_num(state['afterStopCount']).toInt()}',
                        danger: _num(state['afterStopCount']) > 0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.schedule, size: 14, color: AppColors.faint),
                      const SizedBox(width: 6),
                      Text(
                        end == null
                            ? _l10n.lockResetsNext
                            : _l10n.lockResetsAt(_clock, _countdown(end)),
                        style: TextStyle(color: AppColors.faint, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (_hard) ...[
                    FlatCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _l10n.lockHardBody,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _l10n.lockHardBody2,
                            style: TextStyle(
                              color: AppColors.faint,
                              fontSize: 11.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // Only soft offers a release. A hard stop that a button could
                  // undo is a stopped clock: the trader chose the mode that the
                  // terminal will not argue with, and the wall says why.
                  if (!_hard) ...[
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _unfreeze,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open, size: 18),
                      label: Text(
                        _saving ? _l10n.lockUnfreezing : _l10n.lockUnfreezeToday,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Center(
                    child: TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: Text(
                        _l10n.signOut,
                        style: TextStyle(color: AppColors.faint, fontSize: 11),
                      ),
                    ),
                  ),
                  Text(
                    _l10n.lockGreenDay,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 11,
                      height: 1.5,
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

/// The soft lock's notice: MT5 is frozen, the journal is not. It sits above the
/// bottom navigation and opens the same recorded override as the web banner.
class _SoftLockBanner extends StatefulWidget {
  const _SoftLockBanner({
    required this.data,
    required this.api,
    required this.onUnfrozen,
  });

  final Map<String, dynamic> data;
  final JournalApi api;
  final VoidCallback onUnfrozen;

  @override
  State<_SoftLockBanner> createState() => _SoftLockBannerState();
}

class _SoftLockBannerState extends State<_SoftLockBanner>
    with WidgetsBindingObserver {
  bool _saving = false;
  bool? _freezerOn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFreezer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkFreezer();
  }

  Future<void> _checkFreezer() async {
    final enabled = await Mt5Freezer.isEnabled();
    if (mounted) setState(() => _freezerOn = enabled);
  }

  /// Play's Accessibility policy asks for a prominent in-app disclosure and an
  /// explicit yes before the accessibility service and the overlay permission
  /// are requested. The dialog is that disclosure: it names both Android
  /// features, says what the service does and does not see, and only the Agree
  /// button leads to Settings.
  Future<void> _enableFreezer() async {
    final agreed = await showGateDialog<bool>(
      (context) => const _FreezerDisclosureDialog(),
    );
    if (agreed != true) return;
    await Mt5Freezer.openSettings();
  }

  Future<void> _unfreeze() async {
    final reason = await showGateDialog<String>(
      (context) => const _UnfreezeDialog(),
    );
    if (reason == null || reason.trim().length < 10 || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.api.overrideDayStop(reason.trim());
      await Mt5Freezer.sync(active: false);
      if (mounted) widget.onUnfrozen();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.data['state'];
    final used = state is Map && state['lossUsed'] is num
        ? (state['lossUsed'] as num).toDouble()
        : 0.0;
    final limit = state is Map && state['lossLimit'] is num
        ? (state['lossLimit'] as num).toDouble()
        : 0.0;
    final l10n = AppLocalizations.of(context);
    final detail = limit > 0
        ? l10n.lockSoftDetail(
            '\$${used.toStringAsFixed(2)}',
            '\$${limit.toStringAsFixed(2)}',
          )
        : l10n.lockSoftReached;

    // The gate sits above the Navigator, so this notice has no Material
    // ancestor of its own; without one, Text falls back to the debug underline.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 84),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        // The notice itself opens the disclosure while the freezer is off. The
        // tap target stops at the notice's edge, so the tab bar underneath and
        // the Unfreeze button keep their own taps.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _freezerOn == false ? _enableFreezer : null,
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.lockSoftFrozen,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      style: TextStyle(color: AppColors.faint, fontSize: 10.5),
                    ),
                    if (_freezerOn == false)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          l10n.lockFreezerOff,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _unfreeze,
                child: Text(
                  _saving ? l10n.lockUnfreezing : l10n.lockUnfreeze,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.faint,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: danger ? AppColors.danger : AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The prominent disclosure Play requires before an app asks for the
/// accessibility service and "Display over other apps". It has to sit in the
/// app's own UI, be separate from the privacy policy, and end in a clear yes.
class _FreezerDisclosureDialog extends StatelessWidget {
  const _FreezerDisclosureDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final points = <(String, String)>[
      (l10n.lockA11yService, l10n.lockA11yServiceBody),
      (l10n.lockOverlay, l10n.lockOverlayBody),
      (l10n.lockInControl, l10n.lockInControlBody),
    ];
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        l10n.lockFreezerTitle,
        style: TextStyle(
            color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.lockFreezerBody,
              style:
                  TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
            ),
            for (final point in points) ...[
              const SizedBox(height: 12),
              Text(
                point.$1,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                point.$2,
                style: TextStyle(
                    color: AppColors.muted, fontSize: 11.5, height: 1.45),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.lockNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.lockAgree),
        ),
      ],
    );
  }
}

class _UnfreezeDialog extends StatefulWidget {
  const _UnfreezeDialog();

  @override
  State<_UnfreezeDialog> createState() => _UnfreezeDialogState();
}

class _UnfreezeDialogState extends State<_UnfreezeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().length >= 10;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        AppLocalizations.of(context).lockDialogTitle,
        style: TextStyle(
            color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).lockDialogBody,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).lockReasonHint,
              counterText: '',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).lockReasonFoot,
            style: TextStyle(color: AppColors.faint, fontSize: 10.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(AppLocalizations.of(context).lockUnfreeze),
        ),
      ],
    );
  }
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};
