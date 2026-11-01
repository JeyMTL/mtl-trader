// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MTL Trader';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get refresh => 'Refresh';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get navDesk => 'Desk';

  @override
  String get navJournal => 'Journal';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navAccount => 'Account';

  @override
  String get newTrade => 'Journal a trade';

  @override
  String get timeEdge => 'Time edge';

  @override
  String get brandName => 'MTL Trader';

  @override
  String get brandOpenPlans => 'MTL Trader — open payment plans';

  @override
  String get loginHeadline => 'The journal that\nreads you back.';

  @override
  String get loginTagline =>
      'Log the fill, the screenshot and the voice note. Find the hours that pay.';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get emailLabel => 'Email';

  @override
  String get emailHint => 'you@example.com';

  @override
  String get passwordLabel => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get passwordTooShort => 'Use at least 6 characters.';

  @override
  String get loginFootnote =>
      'Google sign-in needs no email confirmation. Email sign-ups must confirm the address before the journal opens.';

  @override
  String get googleOpenFailed =>
      'Could not open Google sign-in. Check that a browser is available, then try again.';

  @override
  String get googleTimedOut =>
      'Google sign-in timed out. Check your connection and try again.';

  @override
  String get googleStartFailed => 'Could not start Google sign-in. Try again.';

  @override
  String get signInUnreachable =>
      'Could not reach the journal. Check your connection and try again.';

  @override
  String get googleFinishNotice =>
      'Finish signing in with Google, then return here — the journal opens on its own.';

  @override
  String confirmEmailNotice(String email) {
    return 'Account created. Open the confirmation link in $email, then sign in here.';
  }

  @override
  String get accountBalance => 'Account balance';

  @override
  String get inProfit => 'In profit';

  @override
  String get inDrawdown => 'In drawdown';

  @override
  String get deposits => 'Deposits';

  @override
  String get bestTrade => 'Best trade';

  @override
  String get worstTrade => 'Worst trade';

  @override
  String netSummary(String pnl, int closed, int wins, int losses) {
    return '$pnl net · $closed closed · ${wins}W / ${losses}L';
  }

  @override
  String get importHistoryHint => 'Import history to plot the curve';

  @override
  String get winRate => 'Win rate';

  @override
  String get profitFactor => 'Profit factor';

  @override
  String get maxDrawdown => 'Max drawdown';

  @override
  String get avgPerTrade => 'Avg / trade';

  @override
  String winnersCount(int count) {
    return '$count winners';
  }

  @override
  String get peakToTrough => 'Peak to trough';

  @override
  String get expectancy => 'Expectancy';

  @override
  String get thisMonth => 'This month';

  @override
  String monthTrades(int count) {
    return '$count trades';
  }

  @override
  String greenDays(int count) {
    return '$count green days';
  }

  @override
  String get monthWinRate => 'Month win rate';

  @override
  String timeEdgeSubtitle(String timezone, String hold) {
    return 'Entry hours in $timezone; sessions in UTC. Median hold $hold.';
  }

  @override
  String get report => 'Report';

  @override
  String get noTimedTradesTitle => 'No timed trades yet';

  @override
  String get noTimedTradesBody =>
      'Set the entry and exit time on a trade. The hour and session report builds itself from that window.';

  @override
  String get mostProfitableHour => 'Most profitable hour';

  @override
  String get mostLosses => 'Most losses';

  @override
  String get bestSession => 'Best session';

  @override
  String get weakestSession => 'Weakest session';

  @override
  String get needsMoreTrades => 'Needs 3+ trades';

  @override
  String periodStats(int trades, String winRate) {
    return '$trades trades · $winRate win';
  }

  @override
  String get thinSampleNote =>
      'Hours with fewer than 3 trades are left out of the best/worst call.';

  @override
  String get journalSectionTitle => 'Journal';

  @override
  String get journalSectionSubtitle =>
      'The notes, screenshots and voice notes behind the fills.';

  @override
  String get nothingJournaledTitle => 'Nothing journaled yet';

  @override
  String get nothingJournaledBody =>
      'Open a trade and add a screenshot or a voice note — it becomes the entry you read later.';

  @override
  String get recentFills => 'Recent fills';

  @override
  String get noFillsTitle => 'No fills recorded';

  @override
  String get startHere => 'Start here';

  @override
  String get startHeadline => 'Three steps to a journal that pays you back.';

  @override
  String get startStep1 => 'Import MT5 history or log your first fill.';

  @override
  String get startStep2 =>
      'Add the entry and exit time — that powers the edge report.';

  @override
  String get startStep3 => 'Attach the chart screenshot and a voice note.';

  @override
  String get seeTimeReport => 'See the time report →';

  @override
  String get couldNotLoadDesk => 'Could not load the desk';

  @override
  String a11yProfit(String amount) {
    return 'Profit of $amount';
  }

  @override
  String a11yLoss(String amount) {
    return 'Loss of $amount';
  }

  @override
  String a11yBreakEven(String amount) {
    return 'Break even, $amount';
  }

  @override
  String a11yEquityCurve(String change) {
    return 'Equity curve. $change since the first recorded day.';
  }

  @override
  String get a11yHourChart => 'Profit and loss by entry hour.';

  @override
  String a11yScreenshots(int count) {
    return '$count screenshots attached';
  }

  @override
  String a11yVoiceNotes(int count) {
    return '$count voice notes attached';
  }

  @override
  String get languageSubtitle =>
      'App labels, month names and dates follow this choice. Saved on this phone.';

  @override
  String get journalTitle => 'Journal';

  @override
  String get journalSearchHint => 'Search symbol, strategy or tag';

  @override
  String get journalSessionAll => 'All sessions';

  @override
  String get journalSessionAsian => 'Asian';

  @override
  String get journalSessionLondon => 'London';

  @override
  String get journalSessionNewYork => 'New York';

  @override
  String get journalSessionSydney => 'Sydney';

  @override
  String get journalFilterAll => 'All';

  @override
  String get journalFilterWins => 'Wins';

  @override
  String get journalFilterLosses => 'Losses';

  @override
  String get journalLoading => 'Loading…';

  @override
  String journalCountSummary(int count, String pnl) {
    return '$count trades · $pnl';
  }

  @override
  String get journalLoadMore => 'Load more';

  @override
  String get journalClearMenu => 'Clear journal';

  @override
  String get journalEmptyTitle => 'No trades found';

  @override
  String get journalEmptyBody =>
      'Tap + to journal a fill, or import your MT5 history on the web desk.';

  @override
  String get journalErrorTitle => 'Could not load the journal';

  @override
  String get deleteTradeTitle => 'Delete this trade?';

  @override
  String deleteTradeBody(String symbol) {
    return '$symbol and its photos or voice notes will be removed. This cannot be undone.';
  }

  @override
  String get deleteAction => 'Delete';

  @override
  String get deleteDone => 'Trade deleted.';

  @override
  String deleteFailed(String error) {
    return 'Could not delete the trade: $error';
  }

  @override
  String get clearJournalTitle => 'Clear the journal?';

  @override
  String get clearJournalBody =>
      'Every trade, photo and voice note in this account is removed. This cannot be undone.';

  @override
  String get clearAllAction => 'Clear all';

  @override
  String clearFailed(String error) {
    return 'Could not clear the journal: $error';
  }

  @override
  String get analyticsEmptyTitle => 'No trades to analyse yet';

  @override
  String get analyticsEmptyBody =>
      'Journal a few entries and the breakdowns fill in automatically.';

  @override
  String get analyticsErrorTitle => 'Could not load analytics';

  @override
  String get analyticsErrorBody => 'Check your connection and try again.';

  @override
  String get timeEdgeDescription =>
      'Best and worst entry hour, sessions and the 24-hour curve.';

  @override
  String get performanceSummaryTitle => 'Performance summary';

  @override
  String get performanceSummarySubtitle =>
      'Every closed trade in your journal.';

  @override
  String get summaryTrades => 'Trades';

  @override
  String summaryTradesFoot(int count) {
    return '$count this month';
  }

  @override
  String summaryWinLoss(int wins, int losses) {
    return '${wins}W · ${losses}L';
  }

  @override
  String summaryGrossFoot(String profit, String loss) {
    return 'Gross $profit / $loss';
  }

  @override
  String get summaryAverageTrade => 'Average trade';

  @override
  String summaryNetFoot(String net) {
    return 'Net $net';
  }

  @override
  String summaryBestTradeFoot(String worst) {
    return 'Worst $worst';
  }

  @override
  String summaryMonthFoot(int count) {
    return '$count winning days';
  }

  @override
  String get monthlyPnlTitle => 'Monthly P&L';

  @override
  String get monthlyPnlSubtitle => 'Last six months';

  @override
  String get pnlByDayTitle => 'P&L by day';

  @override
  String get pnlByDayRecent => 'Last 30 days';

  @override
  String pnlByDayBestWorst(
      String bestDay, String bestPnl, String worstDay, String worstPnl) {
    return 'Best $bestDay $bestPnl · Worst $worstDay $worstPnl';
  }

  @override
  String get legendLoss => 'Loss';

  @override
  String get legendNoTrades => 'No trades';

  @override
  String get legendProfit => 'Profit';

  @override
  String get tapADay => 'Tap a day';

  @override
  String get performanceBySymbol => 'Performance by symbol';

  @override
  String get performanceBySymbolSubtitle => 'Sorted by net P&L';

  @override
  String get performanceByTag => 'Performance by tag';

  @override
  String get performanceByTagSubtitle => 'Tags you add to a trade, rolled up.';

  @override
  String symbolStats(int trades, String winRate) {
    return '${trades}T · $winRate win';
  }

  @override
  String tagStats(int trades, int wins, int losses, String winRate) {
    return '${trades}T · ${wins}W ${losses}L · $winRate';
  }

  @override
  String get a11yRunningCurve =>
      'Running profit and loss for the last 30 days.';

  @override
  String a11yHeatmapDay(String day, String pnl, int trades) {
    return '$day: $pnl, $trades trades';
  }

  @override
  String a11yHeatmapEmpty(String day) {
    return '$day: no trades';
  }
}
