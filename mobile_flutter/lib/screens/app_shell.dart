import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import 'account_screen.dart';
import 'analytics_screen.dart';
import 'backtest_screen.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'edge_screen.dart';
import 'import_screen.dart';
import 'journal_screen.dart';
import 'prop_firm_screen.dart';
import 'trade_form_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  final JournalApi _api = JournalApi();

  /// Quick fade whenever the tab changes, so the shell feels like one surface
  /// rather than five screens snapping in place.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );

  int _index = 0;
  int _reload = 0;
  DateTime? _calendarDay;

  /// Screens are built on first visit and kept mounted. Building all five (and
  /// firing five sets of queries) on launch is what made the first frames
  /// stutter.
  final Map<int, Widget> _built = {};

  /// New synced trades. Realtime is the fast path; the 10-second poll is the
  /// fallback for a project where the trades table is not in the realtime
  /// publication, so the journal still refreshes without a manual pull.
  RealtimeChannel? _tradeChannel;
  Timer? _tradePoll;
  DateTime? _lastSyncedAt;

  /// The newest synced trade that still needs photos or notes. A banner, not a
  /// snackbar: a trader mid-chart will not read a message that disappears.
  Map<String, dynamic>? _needsDetails;

  @override
  void initState() {
    super.initState();
    _startTradeWatch();
  }

  @override
  void dispose() {
    _tradePoll?.cancel();
    _tradeChannel?.unsubscribe();
    _fade.dispose();
    super.dispose();
  }

  DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  Future<Map<String, dynamic>?> _latestSyncedTrade() async {
    final userId = _api.userId;
    if (userId == null) return null;
    return _api.raw
        .from('trades')
        .select('id, symbol, pnl, created_at, position_id')
        .eq('user_id', userId)
        .not('position_id', 'is', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<void> _startTradeWatch() async {
    final userId = _api.userId;
    if (userId == null) return;

    // Prime the cursor so a trade that existed before this launch does not
    // pop a reminder. If this read fails, the first poll primes it instead.
    try {
      final latest = await _latestSyncedTrade();
      _lastSyncedAt = _parseTime(latest?['created_at']);
    } catch (_) {
      // Ignore; the poll handles it.
    }
    if (!mounted) return;

    _tradeChannel = _api.raw
        .channel('journal-trades-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'trades',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            // Only trades that arrived from the broker; a manual entry was
            // written with its details already.
            if (row['position_id'] == null) return;
            _onJournaled(row);
          },
        )
        .subscribe();

    _tradePoll = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollJournal();
    });
  }

  Future<void> _pollJournal() async {
    try {
      final row = await _latestSyncedTrade();
      if (row == null) return;
      final at = _parseTime(row['created_at']);
      if (at == null) return;
      if (_lastSyncedAt == null) {
        _lastSyncedAt = at;
        return;
      }
      if (!at.isAfter(_lastSyncedAt!)) return;
      _lastSyncedAt = at;
      _onJournaled(row);
    } catch (_) {
      // A failed poll is not worth a message; the next one retries.
    }
  }

  void _onJournaled(Map<String, dynamic> row) {
    final at = _parseTime(row['created_at']) ?? DateTime.now().toUtc();
    if (_lastSyncedAt != null && !at.isAfter(_lastSyncedAt!)) return;
    _lastSyncedAt = at;
    if (!mounted) return;

    // Refresh the tabs in place and keep the reminder on screen until it is
    // opened or dismissed.
    _needsDetails = row;
    _invalidate();
  }

  Future<void> _openNeedsDetails() async {
    final row = _needsDetails;
    if (row == null) return;
    setState(() => _needsDetails = null);
    final id = row['id']?.toString();
    if (id != null && id.isNotEmpty) await _openTrade(tradeId: id);
  }

  Widget _journaledBanner() {
    final row = _needsDetails!;
    final symbol = row['symbol']?.toString() ?? 'A trade';
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$symbol journaled',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Add screenshots and notes to finish the record.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openNeedsDetails,
                child: const Text('Add'),
              ),
              IconButton(
                onPressed: () => setState(() => _needsDetails = null),
                icon: Icon(Icons.close, size: 18, color: AppColors.faint),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _fade.value = 0.45;
    _fade.forward();
  }

  void _invalidate() {
    setState(() {
      _reload++;
      _built.clear();
    });
  }

  Future<void> _openTrade({String? tradeId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TradeFormScreen(tradeId: tradeId)),
    );
    if (saved == true && mounted) {
      setState(() {
        _reload++;
        _built.clear();
        _index = 1;
      });
    }
  }

  /// Import is reached from the desk and the account tab rather than a sixth
  /// tab: it is set up once (a statement) and then forgotten, like MT5 sync.
  Future<void> _openImport() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ImportScreen(api: _api)),
    );
    if (imported == true && mounted) _invalidate();
  }

  /// The backtester runs on the server and keeps its own archive, so nothing in
  /// the tabs has to reload when it closes.
  void _openBacktest() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BacktestScreen()),
    );
  }

  void _openPropFirm() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PropFirmScreen(api: _api)),
    );
  }

  void _openEdge() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: Text(AppLocalizations.of(context).timeEdge),
          ),
          body: EdgeScreen(api: _api),
        ),
      ),
    );
  }

  void _openDay(DateTime day) {
    setState(() {
      _calendarDay = day;
      _index = 3;
      _built.remove(3);
    });
  }

  Widget _create(int index) {
    switch (index) {
      case 0:
        return DashboardScreen(
          key: ValueKey('dashboard-$_reload'),
          api: _api,
          onOpenEdge: _openEdge,
          onEdit: (id) => _openTrade(tradeId: id),
          onOpenImport: _openImport,
        );
      case 1:
        return JournalScreen(
          key: ValueKey('journal-$_reload'),
          api: _api,
          onEdit: (id) => _openTrade(tradeId: id),
          onDataChanged: _invalidate,
        );
      case 2:
        return AnalyticsScreen(
          key: ValueKey('analytics-$_reload'),
          api: _api,
          onOpenEdge: _openEdge,
          onOpenDay: _openDay,
        );
      case 3:
        return CalendarScreen(
          key: ValueKey(
            'calendar-$_reload-${_calendarDay?.toIso8601String() ?? 'now'}',
          ),
          api: _api,
          onEdit: (id) => _openTrade(tradeId: id),
          initialDay: _calendarDay,
        );
      default:
        return AccountScreen(
          key: ValueKey('account-$_reload'),
          api: _api,
          onProfileChanged: _invalidate,
          onOpenImport: _openImport,
          onOpenBacktest: _openBacktest,
          onOpenPropFirm: _openPropFirm,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _built.putIfAbsent(_index, () => _create(_index));
    final screens = List<Widget>.generate(
      5,
      (index) => _built[index] ?? const SizedBox.shrink(),
    );

    return Scaffold(
      body: Column(
        children: [
          if (_needsDetails != null) _journaledBanner(),
          Expanded(
            child: FadeTransition(
              opacity: _fade,
              child: IndexedStack(index: _index, children: screens),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTrade(),
        tooltip: l10n.newTrade,
        child: const Icon(Icons.add, size: 24),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withAlpha(16),
                  Colors.transparent,
                ],
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.space_dashboard_outlined),
                  selectedIcon: const Icon(Icons.space_dashboard),
                  label: l10n.navDesk,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.menu_book_outlined),
                  selectedIcon: const Icon(Icons.menu_book),
                  label: l10n.navJournal,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.insights_outlined),
                  selectedIcon: const Icon(Icons.insights),
                  label: l10n.navAnalytics,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month),
                  label: l10n.navCalendar,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: l10n.navAccount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
