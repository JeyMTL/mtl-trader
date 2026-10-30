import 'package:flutter/material.dart';

import '../services/journal_api.dart';
import '../ui/theme.dart';
import 'account_screen.dart';
import 'analytics_screen.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'edge_screen.dart';
import 'journal_screen.dart';
import 'trade_form_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final JournalApi _api = JournalApi();

  int _index = 0;
  int _reload = 0;
  DateTime? _calendarDay;

  /// Screens are built on first visit and kept mounted. Building all five (and
  /// firing five sets of queries) on launch is what made the first frames
  /// stutter.
  final Map<int, Widget> _built = {};

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

  void _openEdge() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: const Text('Time edge'),
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
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    _built.putIfAbsent(_index, () => _create(_index));
    final screens = List<Widget>.generate(
      5,
      (index) => _built[index] ?? const SizedBox.shrink(),
    );

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTrade(),
        tooltip: 'Journal a trade',
        child: const Icon(Icons.add, size: 24),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Desk',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Journal',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Analytics',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
