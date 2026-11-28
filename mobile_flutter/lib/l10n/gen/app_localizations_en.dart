// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MTL Ledger';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get closeLabel => 'Close';

  @override
  String get refresh => 'Refresh';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageSystemSubtitle => 'Follow the device language';

  @override
  String get searchLanguages => 'Search languages';

  @override
  String get noLanguageMatches => 'No language matches that search.';

  @override
  String get languageBuiltIn => 'Built in';

  @override
  String get languageDownload => 'Download';

  @override
  String get languageDownloading => 'Downloading…';

  @override
  String get languageDownloaded => 'Downloaded';

  @override
  String get languageRemove => 'Remove download';

  @override
  String get languageEnglishFallback => 'English until translated';

  @override
  String get languagePackFailed =>
      'Could not download this language. Check your connection and try again.';

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
  String get brandName => 'MTL Ledger';

  @override
  String get brandOpenPlans => 'MTL Ledger — open payment plans';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get rules => 'Rules';

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
  String get loginFooterEncrypted => 'End-to-end encrypted trade logs';

  @override
  String get termsLabel => 'Terms';

  @override
  String get privacyLabel => 'Privacy';

  @override
  String get orSeparator => 'or';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetTitle => 'Reset your password';

  @override
  String get resetBody =>
      'Enter the email on your account and we\'ll send a recovery link.';

  @override
  String get resetSend => 'Send the link';

  @override
  String resetSent(String email) {
    return 'If $email has an account, its recovery link is on the way.';
  }

  @override
  String get resetFailed => 'Could not send the link. Try again in a moment.';

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
  String get balanceAction => 'Add balance';

  @override
  String get balanceTitle => 'Change your balance';

  @override
  String get balanceBody =>
      'The desk reads your balance as your deposits plus this journal\'s profit and loss. It can be changed once a month, so a losing run cannot be reset by topping up.';

  @override
  String get balanceAmount => 'Amount to add';

  @override
  String get balanceNote => 'Note';

  @override
  String get balanceNoteHint => 'e.g. monthly deposit';

  @override
  String get balanceAvailable => 'This month\'s change is still available.';

  @override
  String balanceUsed(String date) {
    return 'This month\'s change is already used. The next one opens on $date.';
  }

  @override
  String get balanceSave => 'Save balance';

  @override
  String get balanceSaved => 'Balance updated.';

  @override
  String get balanceAmountInvalid => 'Enter an amount above zero.';

  @override
  String balanceFailed(String error) {
    return 'Could not save the balance: $error';
  }

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count winners',
      one: '1 winner',
    );
    return '$_temp0';
  }

  @override
  String get peakToTrough => 'Peak to trough';

  @override
  String get expectancy => 'Expectancy';

  @override
  String get thisMonth => 'This month';

  @override
  String monthTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '1 trade',
    );
    return '$_temp0';
  }

  @override
  String greenDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count green days',
      one: '1 green day',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      trades,
      locale: localeName,
      other: '$trades trades',
      one: '1 trade',
    );
    return '$_temp0 · $winRate win';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count screenshots attached',
      one: '1 screenshot attached',
    );
    return '$_temp0';
  }

  @override
  String a11yVoiceNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voice notes attached',
      one: '1 voice note attached',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '1 trade',
    );
    return '$_temp0 · $pnl';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count winning days',
      one: '1 winning day',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      trades,
      locale: localeName,
      other: '$trades trades',
      one: '1 trade',
    );
    return '$day: $pnl, $_temp0';
  }

  @override
  String a11yHeatmapEmpty(String day) {
    return '$day: no trades';
  }

  @override
  String get account => 'Account';

  @override
  String get accountSignOutQuestion => 'Sign out?';

  @override
  String get accountSignOutBody =>
      'Your journal stays on the server. Sign back in any time.';

  @override
  String get signOut => 'Sign out';

  @override
  String get accountPlan => 'Plan';

  @override
  String get accountStatus => 'Status';

  @override
  String get accountTradeLimit => 'Trade limit / month';

  @override
  String get accountUnlimited => 'Unlimited';

  @override
  String get accountTimezone => 'Timezone';

  @override
  String get accountChange => 'Change';

  @override
  String get accountTrialEnds => 'Trial ends';

  @override
  String get accountAccessUntil => 'Access until';

  @override
  String get accountPaidThrough => 'Paid through';

  @override
  String get accountViewPlans => 'View plans & billing';

  @override
  String get accountBuyPlan => 'Buy a subscription';

  @override
  String get accountSubscription => 'Subscription';

  @override
  String get accountSignedIn => 'Signed in';

  @override
  String get accountSubError => 'Could not load your subscription';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonSave => 'Save';

  @override
  String get sectionTrading => 'Trading';

  @override
  String get sectionPreferences => 'Preferences';

  @override
  String get sectionSupport => 'Support';

  @override
  String get sectionAbout => 'About';

  @override
  String get accountAppearance => 'Appearance';

  @override
  String get accountAppearanceBody =>
      'Dark, light, the mark\'s blue, or follow the device. Saved on this phone.';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeBlue => 'Blue';

  @override
  String get themeSystem => 'System';

  @override
  String get accountHelp => 'Help & feedback';

  @override
  String get accountHelpBody =>
      'Questions, bugs, or something the journal should do. Every message is read.';

  @override
  String get accountEmailSupport => 'Email support';

  @override
  String get accountRate => 'Rate MTL Ledger';

  @override
  String get accountAbout => 'About';

  @override
  String get accountAboutBody => 'Where your journal media lives.';

  @override
  String get accountPrivateMedia => 'Private media';

  @override
  String get accountPrivateMediaBody =>
      'Journal photos and voice notes live in a private bucket. Each file is signed for one hour and only your account can request it.';

  @override
  String get accountFooter =>
      'MTL Ledger · flat mobile journal\nTrades, notes and media stay on your Supabase project.';

  @override
  String get accountRules => 'Rules & playbook';

  @override
  String get accountConnectMt5 => 'Connect MT5 account';

  @override
  String get accountImport => 'Import trade history';

  @override
  String get accountBacktest => 'Backtester (Pro)';

  @override
  String get accountPropFirm => 'Prop firm simulation';

  @override
  String get accountTimezoneRow => 'Report timezone';

  @override
  String get accountTimezoneDialog => 'Timezone for the hour report';

  @override
  String accountTimezoneSaved(String zone) {
    return 'Hour report now uses $zone.';
  }

  @override
  String accountTimezoneFailed(String error) {
    return 'Could not save the timezone: $error';
  }

  @override
  String get accountPicture => 'Profile picture';

  @override
  String get accountPictureBody =>
      'Paste a link to an image. Leave it empty to use the picture tied to your email, or your initials when there is none.';

  @override
  String get accountPictureCleared => 'Profile picture cleared.';

  @override
  String get accountPictureUpdated => 'Profile picture updated.';

  @override
  String accountPictureFailed(String error) {
    return 'Could not save the picture: $error';
  }

  @override
  String get accountStoreFailed => 'Could not open the store listing.';

  @override
  String get accountMailFailed =>
      'No mail app was found. Install one and tap the button again.';

  @override
  String get accountDailyStop => 'Daily stop';

  @override
  String get accountDailyStopBody =>
      'What happens when the loss budget or entry cap is reached.';

  @override
  String get accountLossBudget => 'Loss budget';

  @override
  String get accountMaxEntries => 'Max entries';

  @override
  String get accountWhenReached => 'When reached';

  @override
  String get accountOff => 'Off';

  @override
  String get accountNoCap => 'No cap';

  @override
  String get accountLoadingRules => 'Loading your rules…';

  @override
  String get accountEditRules => 'Edit rules and daily stop';

  @override
  String get lockSoft => 'Soft lock';

  @override
  String get lockHard => 'Hard lock';

  @override
  String get lockJournalOnly => 'Journal only';

  @override
  String get accountStopNone =>
      'No stop is set yet. Add a loss budget or an entry cap and the day ends when it is reached.';

  @override
  String get accountStopSoft =>
      'After the stop, MetaTrader 5 on this phone is covered and the journal stays open. Reset from the banner.';

  @override
  String get accountStopHard =>
      'After the stop, the journal locks and the MT5 guard removes resting orders and closes any position opened after it. It clears at the start of your next trading day — a hard stop cannot be lifted.';

  @override
  String get accountStopOff =>
      'After the stop, the journal refuses new entries until the next trading day.';

  @override
  String get rulesIntro =>
      'The checklist you trade by, the days and sessions it applies to, and the stop that ends the day.';

  @override
  String get rulesYourRules => 'Your rules';

  @override
  String get rulesYourRulesBody =>
      'Write them as instructions to yourself: what must be true before entry, what invalidates the trade, and what ends your session.';

  @override
  String get rulesEmpty =>
      'No rules yet. The first one is usually the hardest to keep.';

  @override
  String get rulesAdd => 'Add rule';

  @override
  String get rulesRemove => 'Remove rule';

  @override
  String get rulesDays => 'Days you trade';

  @override
  String get rulesDaysBody =>
      'Reminders only fire on these days. Trading outside them is usually the leak.';

  @override
  String get rulesDailyStop => 'Daily stop';

  @override
  String get rulesDailyStopBody =>
      'The loss budget and entry cap you commit to before the session. Leave both at 0 to switch the stop off.';

  @override
  String get rulesLossBudget => 'Loss budget';

  @override
  String get rulesMaxEntries => 'Max entries';

  @override
  String get rulesWhenReached => 'When the stop is reached';

  @override
  String get rulesJournalOnlyBlurb => 'New entries are refused in the app.';

  @override
  String get rulesSoftBlurb =>
      'MT5 is covered on this phone. The journal stays open.';

  @override
  String get rulesHardBlurb =>
      'The journal locks and the MT5 guard removes resting orders until tomorrow. No reset.';

  @override
  String get rulesSessions => 'Trading sessions';

  @override
  String get rulesSessionsBody =>
      'The windows you actually sit down for. A session that ends before it starts is treated as overnight.';

  @override
  String get rulesNoSessions => 'No sessions yet. Add the window you trade in.';

  @override
  String get rulesSessionName => 'Session name';

  @override
  String get rulesRemoveSession => 'Remove session';

  @override
  String get rulesAddSession => 'Add session';

  @override
  String get rulesNewSession => 'New session';

  @override
  String get rulesSessionFallback => 'Session';

  @override
  String get rulesReminders => 'Remind me before a session';

  @override
  String get rulesRemindersBody =>
      'An in-app reminder with your rules in front of you, before the first trade.';

  @override
  String get rulesRemindersOn => 'Reminders on';

  @override
  String get rulesRemindersOff => 'Reminders off';

  @override
  String get rulesReminderLead => 'How long before';

  @override
  String rulesReminderMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get rulesNotes => 'Notes for yourself';

  @override
  String get rulesNotesHint =>
      'What usually goes wrong, and what you do about it.';

  @override
  String get rulesSave => 'Save rules';

  @override
  String get rulesSaving => 'Saving…';

  @override
  String get rulesSaved => 'Rules saved.';

  @override
  String rulesSaveError(String error) {
    return 'Could not save your rules: $error';
  }

  @override
  String rulesLoadError(String error) {
    return 'Could not load your rules: $error';
  }

  @override
  String get rulesMaxReached =>
      'A playbook holds 20 rules. Fewer is easier to follow.';

  @override
  String get rulesSessionsMax => 'Up to 6 sessions.';

  @override
  String get lockHardBadge => 'HARD LOCK';

  @override
  String get lockSoftBadge => 'SOFT LOCK';

  @override
  String get lockDayOver => 'Your day is over';

  @override
  String lockLossBody(String used, String limit) {
    return 'You reached your loss budget — $used of $limit. The journal is closed until the next session.';
  }

  @override
  String lockCapBody(String trades, String max) {
    return 'You reached your entry cap — $trades of $max entries. The journal is closed until the next session.';
  }

  @override
  String get lockRealised => 'REALISED';

  @override
  String get lockEntries => 'ENTRIES';

  @override
  String get lockAfterStop => 'AFTER STOP';

  @override
  String get lockResetsNext => 'Resets at the next session';

  @override
  String lockResetsAt(String clock, String countdown) {
    return 'Resets $clock · $countdown';
  }

  @override
  String get lockHardBody =>
      'Your MT5 guard removes resting orders while the day is locked and closes any position opened after the stop. It cannot stop a manual market order — only your broker can.';

  @override
  String get lockHardBody2 =>
      'A manual market order can still fill before any EA sees it — only the broker can stop that click. There is no release here: the lock clears at the start of your next trading day.';

  @override
  String get lockUnfreezeToday => 'Lift the stop';

  @override
  String get lockUnfreezing => 'Lifting…';

  @override
  String get lockGreenDay =>
      'Reaching the stop is a green day. The trades you took before it are already in your journal.';

  @override
  String get lockStopReached => 'Your daily stop is reached.';

  @override
  String lockBudgetMessage(String used, String limit) {
    return 'Daily loss budget reached: $used of $limit.';
  }

  @override
  String get lockSoftReached =>
      'The daily stop is reached · the journal stays open';

  @override
  String get lockSoftFrozen => 'Soft lock · guard active';

  @override
  String get lockFreezerOff => 'Freezer is off — tap to turn it on';

  @override
  String get lockUnfreeze => 'Lift the stop';

  @override
  String get lockA11yService => 'Accessibility service';

  @override
  String get lockA11yServiceBody =>
      'Android shows MTL Ledger which app is in front. It never reads what is on the screen, and nothing is sent off the phone.';

  @override
  String get lockOverlay => 'Display over other apps';

  @override
  String get lockOverlayBody =>
      'Lets the journal draw the cover on top of MetaTrader 5 while the day is frozen. No other app is covered.';

  @override
  String get lockInControl => 'You stay in control';

  @override
  String get lockInControlBody =>
      'Both switches live in Android Settings and can be turned off at any time. The journal keeps working without them.';

  @override
  String get lockFreezerTitle => 'Turn on the MT5 freezer?';

  @override
  String get lockFreezerBody =>
      'The freezer needs two Android permissions before it can cover MetaTrader 5 after your daily stop. Android will ask for each one on the next screen.';

  @override
  String get lockNotNow => 'Not now';

  @override
  String get lockAgree => 'Agree';

  @override
  String get lockDialogTitle => 'Lift the stop — once today';

  @override
  String get lockDialogBody =>
      'Saving your reason reopens the day, and the guard stops removing orders on its next poll. It is a grace run, not a reset: the stop re-arms on the trades you take after this, with the same budget — lose that too and the day stays closed.';

  @override
  String get lockReasonHint => 'Why is trading past the stop worth it today?';

  @override
  String get lockReasonFoot =>
      'At least 10 characters. Your broker is not affected by this button.';

  @override
  String lockSoftDetail(String used, String limit) {
    return '$used of $limit · the journal stays open';
  }

  @override
  String get alertsSection => 'Alerts';

  @override
  String get alertsBody =>
      'On this phone, while the app is open. Nothing is sent anywhere.';

  @override
  String get alertsDailyStop => 'Daily stop hit';

  @override
  String get alertsDailyStopBody =>
      'Tell me when the loss limit is reached and trading locks.';

  @override
  String get alertsLevels => 'Level touched';

  @override
  String get alertsLevelsBody =>
      'Tell me when price crosses a level I drew on a chart.';

  @override
  String get alertsJournal => 'Journal reminder';

  @override
  String get alertsJournalBody => 'A daily nudge to log the day.';

  @override
  String get alertsReminderAt => 'Reminder time';

  @override
  String get alertsHistory => 'Notification history';

  @override
  String get alertsHistoryBody =>
      'Everything this phone has alerted on, and why it fired.';

  @override
  String get alertsTitle => 'Alerts';

  @override
  String get alertsEmpty => 'Nothing has fired yet';

  @override
  String get alertsEmptyBody =>
      'When a stop hits or a level is touched, the alert appears here with the reason it fired.';

  @override
  String get alertsWhy => 'Why';

  @override
  String get alertsNotShown => 'not shown';

  @override
  String get alertsClear => 'Clear';

  @override
  String get alertsSendTest => 'Send a test alert';

  @override
  String get alertsPermissionMissing =>
      'Android is not letting this app post notifications. Allow them in system settings.';

  @override
  String planTrialDays(int days) {
    return 'Trial · ${days}d';
  }

  @override
  String get tradeNewEntry => 'New entry';

  @override
  String get tradeEditEntry => 'Edit entry';

  @override
  String get tradeSaveChanges => 'Save changes';

  @override
  String get tradeSaveEntry => 'Save entry';

  @override
  String get tradeInstrument => 'Instrument';

  @override
  String get tradeSymbol => 'Symbol';

  @override
  String get tradePickInstrument => 'Pick an instrument';

  @override
  String get tradeSymbolRequired => 'A symbol is required.';

  @override
  String get tradeBuy => 'BUY';

  @override
  String get tradeSell => 'SELL';

  @override
  String get tradePinLevels => 'Pin levels from chart';

  @override
  String get tradeStrategy => 'Strategy';

  @override
  String get tradeSavedStrategies => 'Saved strategies';

  @override
  String tradeSimilarStrategy(String name) {
    return 'You already use “$name”. Pick the existing spelling so its statistics stay together.';
  }

  @override
  String get tradeExecution => 'Execution';

  @override
  String get tradePrices => 'Prices';

  @override
  String get tradeEntryPrice => 'Entry price';

  @override
  String get tradeStopTarget => 'Stop & target';

  @override
  String get tradeStopLoss => 'Stop loss';

  @override
  String get tradeTakeProfit => 'Take profit';

  @override
  String get tradeExit => 'Exit';

  @override
  String get tradeSizeCosts => 'Size & costs';

  @override
  String get tradeSizeLots => 'Size (lots)';

  @override
  String get tradeCommission => 'Commission';

  @override
  String get tradeSwap => 'Swap';

  @override
  String get tradeNotSet => 'Not set';

  @override
  String get tradeFoundWithExit => 'Found with the exit';

  @override
  String get tradeNotFoundYet => 'Not found yet';

  @override
  String get tradeExitReadsCandles =>
      'The app reads the candles after entry and takes whichever of the two levels the market hit first.';

  @override
  String get tradeFindExit => 'Find exit';

  @override
  String get tradeFindAgain => 'Find again';

  @override
  String get tradeSavedExit => 'Saved exit';

  @override
  String get tradeExitTakeProfit => 'Take profit hit first';

  @override
  String get tradeExitStopLoss => 'Stop loss hit first';

  @override
  String get tradeExitLatestPrice =>
      'Neither level reached · marked at the latest price';

  @override
  String get tradeTimeWindow => 'Time window';

  @override
  String get tradeTimeWindowSub =>
      'Entry and exit time drive the hour and session report.';

  @override
  String get tradeOpened => 'Opened';

  @override
  String get tradeClosed => 'Closed';

  @override
  String get tradeTimeInMarket => 'Time in market';

  @override
  String get tradeSetBothTimes => 'Set both times';

  @override
  String get tradeExitBeforeEntry => 'Exit before entry';

  @override
  String get tradeJournal => 'Journal';

  @override
  String get tradeJournalSub =>
      'What was the setup, and what did you actually do?';

  @override
  String get tradeJournalHint => 'The idea, the trigger, how you managed it.';

  @override
  String get tradeMedia => 'Photos & voice notes';

  @override
  String get tradeMediaSub =>
      'A chart screenshot and a spoken note are worth more than a paragraph later.';

  @override
  String get tradeGallery => 'Gallery';

  @override
  String get tradeCamera => 'Camera';

  @override
  String get tradeRecord => 'Record';

  @override
  String tradeStopRecording(String time) {
    return 'Stop $time';
  }

  @override
  String get tradeAudioFile => 'Audio file';

  @override
  String get tradeUploading => 'Uploading…';

  @override
  String tradeUploadsOnSave(String duration, String size) {
    return '$duration · $size · uploads on save';
  }

  @override
  String get tradeVoiceNote => 'Voice note';

  @override
  String get tradeScreenshots => 'SCREENSHOTS';

  @override
  String get tradeVoiceNotes => 'VOICE NOTES';

  @override
  String get tradeRemoveFileTitle => 'Remove this file?';

  @override
  String get tradeRemoveFileBody =>
      'It is deleted from storage as well as from this entry.';

  @override
  String get tradeRemove => 'Remove';

  @override
  String get tradeTags => 'Tags';

  @override
  String get tradeNoTags => 'No tags yet — they drive the edge report.';

  @override
  String get tradeAddTagHint => 'Add a tag and press enter';

  @override
  String get tradeLiveTicket => 'Live ticket';

  @override
  String get tradeEstimatedPnl => 'ESTIMATED P&L';

  @override
  String tradePips(String pips) {
    return '$pips pips';
  }

  @override
  String get tradeRequired => 'Required';

  @override
  String get tradeNumber => 'Number';

  @override
  String get tradeMustBePositive => 'Must be > 0';

  @override
  String get tradeLevelsHint =>
      'Add a stop loss or a take profit, or the exit is marked at the latest price.';

  @override
  String get tradeLevelBuyStop =>
      'For a BUY the stop loss must be below the entry.';

  @override
  String get tradeLevelBuyTake =>
      'For a BUY the take profit must be above the entry.';

  @override
  String get tradeLevelSellStop =>
      'For a SELL the stop loss must be above the entry.';

  @override
  String get tradeLevelSellTake =>
      'For a SELL the take profit must be below the entry.';

  @override
  String get riskLabel => 'RISK';

  @override
  String get riskRewardLabel => 'REWARD';

  @override
  String get riskHintEmpty =>
      'Add an entry, a level and a size to preview the risk.';

  @override
  String get riskStopWrongBuy =>
      'A buy\'s stop sits below the entry — this one is above it.';

  @override
  String get riskStopWrongSell =>
      'A sell\'s stop sits above the entry — this one is below it.';

  @override
  String get riskTakeWrongBuy =>
      'A buy\'s target sits above the entry — this one is below it.';

  @override
  String get riskTakeWrongSell =>
      'A sell\'s target sits below the entry — this one is above it.';

  @override
  String tradeLoadFailed(String message) {
    return 'Could not load this trade: $message';
  }

  @override
  String tradeSaveFailed(String message) {
    return 'Could not save: $message';
  }

  @override
  String get tradeSaveTimedOut =>
      'The save request timed out. Check your connection and press Save again.';

  @override
  String get tradeMediaSavedNote =>
      'The trade itself was saved — press Save again to retry the media.';

  @override
  String get tradeExitBeforeEntryError =>
      'The exit time cannot be before the entry time.';

  @override
  String get tradeSessionExpired => 'Your session expired. Sign in again.';

  @override
  String get tradeEnterEntryAndSize =>
      'Enter the entry price and the size before saving.';

  @override
  String get tradeSetOpenedTime =>
      'Set the opened time — the candles after it decide the exit price and time.';

  @override
  String get tradePickSymbolFirst =>
      'Pick the symbol from the list — the exit is read from its candles.';

  @override
  String get tradeOpenedInFuture =>
      'The opened time is in the future. Pick a past time.';

  @override
  String get tradeEnterEntryFirst => 'Enter the entry price first.';

  @override
  String get tradePickSymbolToFindExit =>
      'Pick a symbol from the list first, then find the exit.';

  @override
  String get tradeNoCandles =>
      'No candles were returned for that time. Check the symbol and the opened time, then try again.';

  @override
  String get tradeCandlesUnreadable =>
      'The candles could not be read. Check your connection and try again.';

  @override
  String tradeRemovePendingFailed(String message) {
    return 'The file was removed here but could not be deleted from storage: $message';
  }

  @override
  String tradeRemoveFailed(String message) {
    return 'Could not remove that file: $message';
  }

  @override
  String get tradeRecordingOpenFailed => 'Could not open that recording.';

  @override
  String get tradeRecordingPlayFailed => 'Could not play that recording.';

  @override
  String journalRefreshFailed(String message) {
    return 'Could not refresh: $message';
  }

  @override
  String journalRescueBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades are',
      one: '1 trade is',
    );
    return 'Your $_temp0 saved, but the list came back empty — most often a dropped session. Pull down to try again.';
  }

  @override
  String journalRowLine(String date, String entry, String exit, String lots) {
    return '$date · $entry → $exit · $lots lots';
  }

  @override
  String get journalResult => 'Result';

  @override
  String syncedOne(String symbol, String pnl) {
    return '$symbol synced · $pnl';
  }

  @override
  String syncedMany(int count, String pnl) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades synced',
      one: '1 trade synced',
    );
    return '$_temp0 · $pnl';
  }

  @override
  String journaledTitle(String symbol) {
    return '$symbol journaled';
  }

  @override
  String get journaledBody => 'Add screenshots and notes to finish the record.';

  @override
  String get aTrade => 'A trade';

  @override
  String get calendarPreviousMonth => 'Previous month';

  @override
  String get calendarNextMonth => 'Next month';

  @override
  String get calendarNoTrades => 'No trades';

  @override
  String calendarMonthFoot(String pnl, int trades, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$pnl · ${trades}T · $_temp0';
  }

  @override
  String get calendarLoadFailed => 'Could not load this month';

  @override
  String get calendarLegendWin => 'Winning day';

  @override
  String get calendarLegendLoss => 'Losing day';

  @override
  String get calendarDayEmpty => 'No trades loaded for this day.';

  @override
  String get symbolSearchHint => 'Search pairs, metals, indices, crypto';

  @override
  String get symbolNoMatchTitle => 'No instrument matches';

  @override
  String get symbolNoMatchBody =>
      'Try a shorter search, or type the symbol directly.';

  @override
  String symbolFooter(int count) {
    return '$count instruments · every chart is a live OANDA CFD quote';
  }

  @override
  String get timeFrameTitle => 'Time frame';

  @override
  String get timeFrameNotServed => 'Not served by this chart feed yet';

  @override
  String get screenshotFailed => 'Could not load this screenshot.';

  @override
  String get confirmTitle => 'Confirm your email';

  @override
  String confirmBody(String email) {
    return 'The journal opens once $email is confirmed. Open the link Supabase emailed you, then return here.';
  }

  @override
  String get confirmChecked =>
      'Checked. If the journal did not open, sign out and back in.';

  @override
  String get confirmCheckFailed =>
      'Could not check yet. Try again in a moment.';

  @override
  String get confirmResent =>
      'Confirmation link sent. Check your inbox and spam folder.';

  @override
  String get confirmResendFailed =>
      'Could not resend the email. Try again in a minute.';

  @override
  String get confirmCheckedAction => 'I have confirmed';

  @override
  String get confirmResendAction => 'Resend confirmation';

  @override
  String get confirmOtherAccount => 'Use another account';

  @override
  String get edgeLoadFailed => 'Could not load the edge report';

  @override
  String get edgeWhenYouWin => 'WHEN YOU WIN';

  @override
  String get edgeIntro =>
      'The journal ranks every entry hour and session by realised P&L.';

  @override
  String edgeZonePill(String zone) {
    return '$zone TIME';
  }

  @override
  String get edgeEmptyTitle => 'No time windows yet';

  @override
  String get edgeEmptyBody =>
      'Open a trade and set the entry and exit time. The hour and session report is built from that window.';

  @override
  String get edgeGroupTimeOfDay => 'Time of day';

  @override
  String get edgeGroupSessions => 'Sessions';

  @override
  String get edgeBestHour => 'Most profitable hour';

  @override
  String get edgeWorstHour => 'Most losses';

  @override
  String get edgeBestSession => 'Best session';

  @override
  String get edgeWorstSession => 'Weakest session';

  @override
  String get edgeByHourTitle => 'P&L by entry hour';

  @override
  String get edgeByHourSub =>
      '24-hour clock in your timezone; sessions use UTC.';

  @override
  String edgeExcluded(int min, String median, int timed) {
    String _temp0 = intl.Intl.pluralLogic(
      timed,
      locale: localeName,
      other: '$timed timed trades',
      one: '1 timed trade',
    );
    return 'Windows with fewer than $min trades are excluded from best/worst. Median hold $median across $_temp0.';
  }

  @override
  String get edgeSessionsSub =>
      'UTC market windows: Asian 00–08 · London 08–13 · overlap 13–16 · New York 16–21 · late 21–24.';

  @override
  String edgeNeedTrades(int min) {
    return 'Need $min+ trades';
  }

  @override
  String get edgeNotEnoughSample => 'Not enough sample';

  @override
  String edgeCardFoot(int trades, String winRate) {
    String _temp0 = intl.Intl.pluralLogic(
      trades,
      locale: localeName,
      other: '$trades trades',
      one: '1 trade',
    );
    return '$_temp0 · $winRate win';
  }

  @override
  String get toolLong => 'Long position';

  @override
  String get toolShort => 'Short position';

  @override
  String get toolTrendLine => 'Trend line';

  @override
  String get toolRay => 'Horizontal ray';

  @override
  String get toolVertical => 'Vertical line';

  @override
  String get toolRectangle => 'Rectangle';

  @override
  String get toolEllipse => 'Ellipse';

  @override
  String get toolFibRetracement => 'Fib retracement';

  @override
  String get toolFibExtension => 'Fib extension';

  @override
  String get toolMeasure => 'Measure';

  @override
  String get toolText => 'Text';

  @override
  String get toolArrowUp => 'Arrow up';

  @override
  String get toolArrowDown => 'Arrow down';

  @override
  String get toolBrush => 'Brush';

  @override
  String get catAll => 'All';

  @override
  String get catPositions => 'Position';

  @override
  String get catTrend => 'Trend';

  @override
  String get catShapes => 'Shapes';

  @override
  String get catFib => 'Fib';

  @override
  String get catNotes => 'Notes';

  @override
  String get catMeasure => 'Measure';

  @override
  String get toolsSearchHint => 'Search tools';

  @override
  String toolsNoMatch(String query) {
    return 'No tool matches “$query”.';
  }

  @override
  String get toolsPinnedHeader => 'PINNED';

  @override
  String get toolsPinHint => 'Long-press a tool to pin it';

  @override
  String get toolsUnpinHint => 'Long-press to remove';

  @override
  String toolsPinnedA11y(String tool) {
    return '$tool, pinned';
  }

  @override
  String toolsPinnedNotice(String tool) {
    return '$tool pinned to the top';
  }

  @override
  String toolsUnpinnedNotice(String tool) {
    return '$tool unpinned';
  }

  @override
  String get magnetLabel => 'Magnet';

  @override
  String get magnetOff => 'Off';

  @override
  String get magnetWeak => 'Weak';

  @override
  String get magnetStrong => 'Strong';

  @override
  String get continuousLabel => 'Continuous';

  @override
  String get switchOn => 'On';

  @override
  String get switchOff => 'Off';

  @override
  String get closeAction => 'Close';

  @override
  String get chartToolsTitle => 'Chart tools';

  @override
  String get chartToolsBody =>
      'Pick a tool and it lands on the chart — drag it to calibrate the levels. Tap any object for edit, clone or delete.';

  @override
  String get selectedObject => 'SELECTED OBJECT';

  @override
  String get objectEdit => 'Edit';

  @override
  String get objectEditSub => 'Set levels';

  @override
  String get objectClone => 'Clone';

  @override
  String get objectCloneSub => 'Copy it';

  @override
  String get objectDelete => 'Delete';

  @override
  String get objectDeleteSub => 'Remove';

  @override
  String get manageSection => 'MANAGE';

  @override
  String get undoLast => 'Undo last change';

  @override
  String get redoAction => 'Redo';

  @override
  String get objectTree => 'Object tree';

  @override
  String get analysisHub => 'Analysis hub';

  @override
  String get analysisHubSub => 'Layouts, settings, studies, alerts';

  @override
  String get clearDrawings => 'Clear all drawings';

  @override
  String get deskToday => 'Today';

  @override
  String get deskThisWeek => 'This week';

  @override
  String get deskMonthTrades => 'Trades this month';

  @override
  String get rMultipleTitle => 'R-multiple distribution';

  @override
  String rMultipleSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades sized against their stops.',
      one: '1 trade sized against its stop.',
    );
    return '$_temp0';
  }

  @override
  String get rMultipleEmptyTitle => 'No risk multiples yet';

  @override
  String get rMultipleEmptyBody =>
      'Set a stop loss on a trade. Each one then counts in multiples of the risk it took.';

  @override
  String rMultipleFoot(String average) {
    return 'Average $average per trade';
  }

  @override
  String get strategyLeaderboard => 'Strategy leaderboard';

  @override
  String get strategyLeaderboardSub =>
      'Ranked by what each trade earns, not by the total.';

  @override
  String get sessionHeatmap => 'Session heatmap';

  @override
  String get sessionHeatmapSub =>
      'Where the money was made, session by session.';

  @override
  String get symbolFavorites => 'Favorites';

  @override
  String get daySummaryTitle => 'Selected day';

  @override
  String get daySummaryHint => 'Tap a day with trades to see its numbers here.';

  @override
  String get daySummaryViewTrades => 'All trades';

  @override
  String get symbolPickerTitle => 'Instruments';

  @override
  String get allAssets => 'All instruments';

  @override
  String get symbolNoFavoritesTitle => 'No pinned instruments';

  @override
  String get symbolNoFavoritesBody =>
      'Star the instruments you watch. They stay at the top of this list.';

  @override
  String get pin => 'Pin to favorites';

  @override
  String get unpin => 'Remove from favorites';

  @override
  String get keepAction => 'Keep';

  @override
  String get doneAction => 'Done';

  @override
  String get importTitle => 'Import trades';

  @override
  String get importUnreadableFile =>
      'Could not read that file. Try picking it again.';

  @override
  String importFileTooLarge(String size) {
    return 'That file is $size MB. Imports are limited to 20 MB — split the report and import it in parts.';
  }

  @override
  String get importNoClosedTrades =>
      'No closed trades were found. Make sure the file is an MT5 or broker history export — open positions are skipped.';

  @override
  String get importNoReadableData =>
      'No readable data in this file. Export it as CSV from MT5 or your broker and try again.';

  @override
  String get importUnknownFile => 'Unknown file';

  @override
  String get importDeleteTitle => 'Delete this import?';

  @override
  String importDeleteBody(int count, String filename) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count trades from $filename will be removed from your journal. This cannot be undone.',
      one:
          '1 trade from $filename will be removed from your journal. This cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count imported trades.',
      one: 'Deleted 1 imported trade.',
    );
    return '$_temp0';
  }

  @override
  String get importImporting => 'Importing…';

  @override
  String importAction(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Import $count trades',
      one: 'Import 1 trade',
    );
    return '$_temp0';
  }

  @override
  String get importChooseAnother => 'Choose another file';

  @override
  String get importReadingFile => 'Reading file…';

  @override
  String get importChooseFile => 'Choose a trade history file';

  @override
  String get importFileTypes =>
      'MT5 XML report, CSV, TSV, an Excel .xlsx/.xls export, or a broker CSV.';

  @override
  String get importSkippedNote =>
      'Already-imported tickets are skipped, so importing the same statement twice does not double your journal.';

  @override
  String get importSelectedFile => 'Selected file';

  @override
  String get importNoTradesFound => 'No closed trades found';

  @override
  String importFileStats(int trades, int wins, int losses) {
    String _temp0 = intl.Intl.pluralLogic(
      trades,
      locale: localeName,
      other: '$trades trades',
      one: '1 trade',
    );
    String _temp1 = intl.Intl.pluralLogic(
      wins,
      locale: localeName,
      other: '$wins wins',
      one: '1 win',
    );
    String _temp2 = intl.Intl.pluralLogic(
      losses,
      locale: localeName,
      other: '$losses losses',
      one: '1 loss',
    );
    return '$_temp0 · $_temp1 · $_temp2';
  }

  @override
  String get importRemoveFile => 'Remove file';

  @override
  String get importNetPnl => 'Net P&L';

  @override
  String get importDateRange => 'Date range';

  @override
  String get importPreview => 'Preview';

  @override
  String importPreviewSub(int shown, int total) {
    return 'First $shown of $total';
  }

  @override
  String importPreviewLine(String type, String lot) {
    return '$type · $lot lots';
  }

  @override
  String get importNothingNew => 'Nothing new to import';

  @override
  String get importComplete => 'Import complete';

  @override
  String importAlreadyInJournal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades are already in your journal.',
      one: '1 trade is already in your journal.',
    );
    return '$_temp0';
  }

  @override
  String importAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades added to your journal.',
      one: '1 trade added to your journal.',
    );
    return '$_temp0';
  }

  @override
  String importDuplicatesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count duplicates skipped.',
      one: '1 duplicate skipped.',
    );
    return '$_temp0';
  }

  @override
  String get importAnother => 'Import another file';

  @override
  String get importClearBody =>
      'Every trade — imported or logged by hand — will be deleted. This cannot be undone.';

  @override
  String get importClearAction => 'Clear journal';

  @override
  String get importJournalCleared => 'Journal cleared.';

  @override
  String get importHistoryTitle => 'Import history';

  @override
  String get importHistorySub => 'Statements imported from this device.';

  @override
  String get importHistoryEmpty => 'No imports yet.';

  @override
  String importHistoryLine(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '1 trade',
    );
    return '$_temp0 · $when';
  }

  @override
  String get importDeleteTooltip => 'Delete this import';

  @override
  String get importHowToTitle => 'How to export from MT5';

  @override
  String get importHowToSteps =>
      '1. Open MetaTrader 5 → History tab.\n2. Right-click → All History, then select the trades.\n3. Right-click → Report / Export and save as CSV or the XML report (ReportHistory files).\n4. Pick that file above.';

  @override
  String get importNetNote =>
      'P&L is stored net: MT5 profit plus commission and swap. Excel .xlsx and .xls exports work too — .xls up to 4 MB is read on our server, so larger ones should be saved as .xlsx or CSV.';

  @override
  String get syncTitle => 'MT5 Sync';

  @override
  String get syncSubmitting =>
      'Signing in now. The first sync can take a few minutes — we will notify you when it is live.';

  @override
  String get syncDisconnectTitle => 'Disconnect account?';

  @override
  String get syncDisconnectBody =>
      'We delete the stored password and stop syncing. Your trades stay in your journal.';

  @override
  String get syncDisconnectAction => 'Disconnect';

  @override
  String get syncNotYet => 'not yet';

  @override
  String syncSecondsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}s ago',
      one: '1s ago',
    );
    return '$_temp0';
  }

  @override
  String syncMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}m ago',
      one: '1m ago',
    );
    return '$_temp0';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}h ago',
      one: '1h ago',
    );
    return '$_temp0';
  }

  @override
  String syncDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}d ago',
      one: '1d ago',
    );
    return '$_temp0';
  }

  @override
  String get syncStatusConnected => 'Connected';

  @override
  String get syncStatusConnecting => 'Connecting…';

  @override
  String get syncStatusFailed => 'Connection failed';

  @override
  String get syncStatusDisconnected => 'Disconnected';

  @override
  String get syncCurrent => 'Current connection';

  @override
  String get syncBroker => 'Broker';

  @override
  String get syncServer => 'Server';

  @override
  String get syncAccount => 'Account';

  @override
  String get syncLastTrade => 'Last trade';

  @override
  String get syncHintConnected =>
      'Closed trades arrive automatically, even with the app shut.';

  @override
  String syncHintStalledError(String error) {
    return 'Still not connected. The sync host reported: $error';
  }

  @override
  String get syncHintStalledConnecting =>
      'Still signing in. The first sync reads up to a year of closed trades from the terminal, so it can take several minutes. Leave it connected and pull down to refresh.';

  @override
  String get syncHintStalled =>
      'Still not connected after two minutes, and nothing has reported a sign-in attempt. The sync service is probably not running — start it, then disconnect here and connect again.';

  @override
  String get syncHintConnecting =>
      'Signing in and reading your closed trades. A first sync can take a few minutes while the terminal downloads history. You can close the app: we send a notification when sync is live, or if the password is wrong.';

  @override
  String get syncHintPending =>
      'Waiting for a sync session to pick this account up. If it stays here, check the account number, server and investor password.';

  @override
  String get syncMailFailed => 'Could not open your mail app.';

  @override
  String get syncContactSupport => 'Contact support';

  @override
  String get syncDisconnectLong => 'Disconnect and delete password';

  @override
  String get syncSearchBrokers => 'Search MT5 brokers';

  @override
  String get syncDemo => 'DEMO';

  @override
  String get syncLive => 'LIVE';

  @override
  String syncLastAttempt(String details) {
    return 'Last attempt: $details';
  }

  @override
  String get syncConnectTitle => 'Connect automatically';

  @override
  String get syncConnectBody =>
      'No PC needed. Enter the account details once and every closed trade lands in your journal. The first connection can take a few minutes while we download your trade history.';

  @override
  String get syncAccountNumber => 'Account number';

  @override
  String get syncInvestorPassword => 'Investor (read-only) password';

  @override
  String get syncInvestorNote =>
      'Use the investor password, never your trading password: MT5 → Settings → your account → Change investor password. It cannot trade, it is stored encrypted, and changing it in MT5 instantly cuts our access.';

  @override
  String get syncConnectAction => 'Connect account';

  @override
  String get syncAfterConnect =>
      'After you connect, you can close the app. The first sync can take a few minutes, and we send a notification when it is live — or if the password is wrong.';

  @override
  String get syncUseTyped => 'Use what you typed';

  @override
  String get syncBrokersUnavailableTitle => 'Broker list unavailable';

  @override
  String get syncBrokersUnavailableBody =>
      'Type the broker name in the field and it will be used as is.';

  @override
  String get syncTypeServer => 'Type the server name';

  @override
  String syncBrokerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count MT5 brokers',
      one: '1 MT5 broker',
    );
    return '$_temp0 · any broker works, even one not listed';
  }

  @override
  String get backtestTitle => 'Backtest';

  @override
  String get backtestIntro =>
      'Replay your own rules over your own MT5 bar data, with costs and the fill assumptions printed on the result.';

  @override
  String get backtestCustom => 'Custom backtest';

  @override
  String get backtestFileUnreadable =>
      'Could not read that file. Try picking it again.';

  @override
  String get backtestFileTooLarge =>
      'That file is over 4 MB. Export a shorter range.';

  @override
  String get backtestNeedData => 'Upload or paste the bar data first.';

  @override
  String get backtestRunSaved => 'Run complete and saved.';

  @override
  String get backtestRunUnsaved => 'Run complete — the archive write failed.';

  @override
  String get backtestRunFailed => 'The run could not be completed. Try again.';

  @override
  String get backtestLoadRunFailed => 'Could not load that run.';

  @override
  String get backtestDeleteTitle => 'Delete this saved run?';

  @override
  String get backtestThisRun => 'This run';

  @override
  String get backtestRunDeleted => 'Run deleted.';

  @override
  String get backtestDeleteFailed => 'Could not delete the run.';

  @override
  String get backtestSimulating => 'Simulating…';

  @override
  String get backtestRunAction => 'Run backtest';

  @override
  String get backtestBarsTitle => '1. Bar data';

  @override
  String get backtestChooseCsv => 'Choose a CSV or paste below';

  @override
  String get clearAction => 'Clear';

  @override
  String get backtestBarsHint =>
      'Up to 60,000 bars. In MT5: select the chart with Ctrl+A, copy, paste into a text file.';

  @override
  String get backtestRulesTitle => '2. Rules';

  @override
  String get backtestRunName => 'Run name';

  @override
  String get backtestRunNameHint => 'e.g. EURUSD M1 SMA cross';

  @override
  String get backtestSymbol => 'Symbol';

  @override
  String get backtestTimeframe => 'Timeframe';

  @override
  String get backtestRulesLabel => 'Rules';

  @override
  String get backtestCompiledRules => 'Compiled rules';

  @override
  String get backtestUseBuiltIn => 'Use a built-in rule set instead';

  @override
  String get backtestCostsTitle => '3. Sizing and costs';

  @override
  String get backtestStartingBalance => 'Starting balance';

  @override
  String get backtestRiskPercent => 'Risk per trade %';

  @override
  String get backtestContractSize => 'Contract size';

  @override
  String get backtestMaxLeverage => 'Max leverage';

  @override
  String get backtestSpread => 'Spread (price)';

  @override
  String get backtestSlippage => 'Slippage (price)';

  @override
  String get backtestCommission => 'Commission / trade';

  @override
  String get backtestInSampleShare => 'In-sample share';

  @override
  String get backtestClockOffset => 'Server clock offset (min)';

  @override
  String get backtestEmptyTitle => 'No run yet';

  @override
  String get backtestEmptyBody =>
      'Upload a history export, choose the rules and the cost model, and the report appears here with its assumptions.';

  @override
  String get backtestReturn => 'Return';

  @override
  String get backtestSharpe => 'Sharpe';

  @override
  String get backtestExposure => 'Exposure';

  @override
  String get backtestAvgR => 'Avg R';

  @override
  String backtestBarsLine(String bars, String range, String timeframe) {
    return '$bars bars · $range · $timeframe';
  }

  @override
  String get backtestEquity => 'Equity';

  @override
  String get backtestSplitTitle => 'In-sample vs out-of-sample';

  @override
  String get backtestSplitBody =>
      'Two independent runs from the same balance. The second window knows nothing the first produced — the closest thing to an out-of-sample test one file can give you.';

  @override
  String get backtestColWindow => 'Window';

  @override
  String get backtestColTrades => 'Trades';

  @override
  String get backtestColNet => 'Net';

  @override
  String get backtestColWin => 'Win';

  @override
  String get backtestColMaxDd => 'Max DD';

  @override
  String get backtestInSample => 'In-sample';

  @override
  String get backtestOutOfSample => 'Out-of-sample';

  @override
  String get backtestAssumptions => 'Assumptions';

  @override
  String backtestTradesTitle(int count) {
    return 'Trades ($count)';
  }

  @override
  String get backtestColSide => 'Side';

  @override
  String get backtestColEntry => 'Entry';

  @override
  String get backtestColLots => 'Lots';

  @override
  String get backtestColPnl => 'P&L';

  @override
  String get backtestColWhy => 'Why';

  @override
  String get backtestSavedRuns => 'Saved runs';

  @override
  String get backtestSavedSub => 'Runs from this account, on any device.';

  @override
  String get backtestNoSavedRuns => 'No saved runs yet.';

  @override
  String backtestRunFallback(String symbol) {
    return '$symbol run';
  }

  @override
  String backtestDeleteTooltip(String name) {
    return 'Delete $name';
  }

  @override
  String get cbIntro =>
      'Write the setup in your own words. The server turns it into a rule set, shows you the rules in plain English, and only then can you run them over your bar data.';

  @override
  String get cbGalleryFailed =>
      'Could not open the gallery. Check the photo permission and try again.';

  @override
  String get cbUseImage => 'Use a PNG, JPEG or WebP screenshot.';

  @override
  String cbReadFailed(String name) {
    return 'Could not read $name. Try picking it again.';
  }

  @override
  String cbTooManyCharts(int max) {
    return 'Up to $max charts.';
  }

  @override
  String get cbChartTooLarge =>
      'That screenshot is over 4 MB. Crop it to the setup.';

  @override
  String get cbChartsBudget =>
      'Those charts are too large to send together. Remove one, or crop it.';

  @override
  String get cbNothingRecorded =>
      'Nothing was recorded. Hold on, speak, then stop.';

  @override
  String get cbVoiceAdded => 'Voice note added to the description.';

  @override
  String get cbRecordingFailed =>
      'Could not use that recording. Type the explanation instead.';

  @override
  String get cbDescribeFirst =>
      'Describe the setup in at least a sentence — what has to happen before you take the trade?';

  @override
  String get cbCompileFailed =>
      'The description could not be compiled. Check your connection and try again.';

  @override
  String get cbStepSetup => '1. The setup';

  @override
  String get cbDescriptionHint =>
      'e.g. Wait for the London open, then buy when price closes above the previous 20-bar high and the 200 EMA is rising. Exit at 2R or when the 20 high is lost.';

  @override
  String get cbSymbolOptional => 'Symbol (optional)';

  @override
  String get cbStopOptional => 'Stop rule (optional)';

  @override
  String get cbCriteriaLabel => 'Your definition of a valid setup (optional)';

  @override
  String get cbCompiling => 'Compiling rules…';

  @override
  String get cbCompileAction => 'Compile rules';

  @override
  String get cbNoChartsSent => 'no charts sent';

  @override
  String cbChartsSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count charts sent',
      one: '1 chart sent',
    );
    return '$_temp0';
  }

  @override
  String cbRulesLine(String timeframe, String charts) {
    return '$timeframe · $charts · check every line before you run it';
  }

  @override
  String cbCompiledWith(String model) {
    return 'Compiled with $model';
  }

  @override
  String get cbUseRules => 'Use these rules';

  @override
  String get cbCompileAgain => 'Compile again';

  @override
  String get cbAddChart => 'Add chart';

  @override
  String cbAddChartCount(int current, int max) {
    return 'Add chart ($current/$max)';
  }

  @override
  String cbStopRecording(int seconds) {
    return 'Stop · ${seconds}s';
  }

  @override
  String get cbTranscribing => 'Transcribing…';

  @override
  String get cbVoiceNote => 'Voice note';

  @override
  String cbAttachmentsNote(int max) {
    return 'Up to $max chart screenshots and a 60-second voice note. The charts are sent to the model with the description; the note is transcribed into the description and never stored.';
  }

  @override
  String get cbTimeframe => 'Timeframe';

  @override
  String get cbConfirmation => 'Confirmation (optional)';

  @override
  String get cbNone => 'None';

  @override
  String get chartDrawingTools => 'Drawing tools';

  @override
  String get chartMarketReplay => 'Market replay';

  @override
  String get chartStyle => 'Chart style';

  @override
  String chartMagnetTooltip(String mode) {
    return 'Magnet: $mode';
  }

  @override
  String get chartHideBuySell => 'Hide buy and sell';

  @override
  String get chartBuySell => 'Buy / sell';

  @override
  String chartTitle(String symbol) {
    return '$symbol · chart';
  }

  @override
  String get chartFullscreen => 'Fullscreen';

  @override
  String get chartExitFullscreen => 'Exit fullscreen';

  @override
  String get chartExitTimeBeforeEntry =>
      'The exit time is before the entry time.';

  @override
  String get chartHeadsUp => 'You can still save it — this is only a heads-up.';

  @override
  String get chartDragLevel => 'Drag a level line to move it and its time';

  @override
  String get chartCrosshairOn => 'Crosshair mode on';

  @override
  String get chartCrosshairOff => 'Crosshair mode off';

  @override
  String get chartStopBuyBelow => 'For a BUY the stop is normally below entry.';

  @override
  String get chartStopSellAbove =>
      'For a SELL the stop is normally above entry.';

  @override
  String get chartTargetBuyAbove =>
      'For a BUY the target is normally above entry.';

  @override
  String get chartTargetSellBelow =>
      'For a SELL the target is normally below entry.';

  @override
  String get chartUnreachableAccount =>
      'This chart could not reach your account. The levels on this device are unaffected.';

  @override
  String chartIntervalRefused(String interval) {
    return '$interval candles are not served by this chart feed yet — showing 1M.';
  }

  @override
  String get chartNoCandlesWindow =>
      'No candles in that time frame. Try a wider window.';

  @override
  String get chartPlacementMove => 'Move to size it, then lift to finish';

  @override
  String get chartPlacementLift => 'Lift to place';

  @override
  String get chartPlacementTapFirst => 'Tap to set the first point';

  @override
  String get chartPlacementTap => 'Tap to place';

  @override
  String chartPlacedOfTotal(int placed, int total) {
    return '$placed of $total';
  }

  @override
  String chartMagnetSuffix(String mode) {
    return '$mode magnet';
  }

  @override
  String get chartKeepDrawingOn => 'Keep drawing on';

  @override
  String get chartKeepDrawingOff => 'Keep drawing off';

  @override
  String get chartPutToolAway => 'Put the tool away';

  @override
  String get chartMoreActions => 'More actions';

  @override
  String get chartClone => 'Clone';

  @override
  String get chartColour => 'Colour';

  @override
  String get chartLineWidth => 'Line width';

  @override
  String get chartLineStyle => 'Line style';

  @override
  String get chartLock => 'Lock';

  @override
  String get chartUnlock => 'Unlock';

  @override
  String get chartShow => 'Show';

  @override
  String get chartHide => 'Hide';

  @override
  String get chartRemove => 'Remove';

  @override
  String chartAddAlertAt(String symbol, String price) {
    return 'Add alert on $symbol at $price';
  }

  @override
  String get chartAlertSubtitle =>
      'A line that fires when price reaches this level';

  @override
  String get chartPinLevel => 'Pin a level here';

  @override
  String get chartPinSubtitle => 'A plain line, no notification';

  @override
  String get chartUseAsEntry => 'Use as entry';

  @override
  String get chartUseAsEntrySub =>
      'Fills the entry price and this candle’s time';

  @override
  String get chartCopyPrice => 'Copy price';

  @override
  String chartAlertSet(String price) {
    return 'Alert set at $price.';
  }

  @override
  String chartLevelPinned(String price) {
    return 'Level pinned at $price.';
  }

  @override
  String chartPriceCopied(String price) {
    return '$price copied.';
  }

  @override
  String get chartReplayFromDate => 'Replay from a date';

  @override
  String chartNoCandlesFor(String date) {
    return 'No candles for $date.';
  }

  @override
  String chartFeedDown(String at) {
    return 'Feed down — showing this window from the copy saved $at.';
  }

  @override
  String get chartNoEarlierCandles => 'No earlier candles for this range.';

  @override
  String get chartProIntervals =>
      '5s, 10s and 15s candles are a Pro feature. Basic charts run from 30s up.';

  @override
  String get chartBasicIntervals =>
      '30s and 45s candles are part of Basic. Free charts run from 1m up.';

  @override
  String get chartPinUpgrade =>
      'Pinning entry, stop and target on the chart is part of Basic. Upgrade to pin your levels — the chart itself and every other drawing tool stay free.';

  @override
  String get chartReplayUpgrade =>
      'Market replay is a Pro feature. Upgrade to Pro to use it.';

  @override
  String get chartLoadEarlier => 'Load earlier candles';

  @override
  String get chartPreviousBar => 'Previous bar';

  @override
  String get chartNextBar => 'Next bar';

  @override
  String get chartPauseReplay => 'Pause replay';

  @override
  String get chartPlayReplay => 'Play replay';

  @override
  String get chartJumpToDate => 'Jump to a date';

  @override
  String get chartExitReplay => 'Exit';

  @override
  String get chartNoteHint => 'Note on the chart';

  @override
  String get chartAdd => 'Add';

  @override
  String get chartAlertLine => 'Alert line';

  @override
  String get chartAlertLineFired => 'Alert line — fired';

  @override
  String chartTextWith(String body) {
    return 'Text — $body';
  }

  @override
  String chartPositionSummary(
      String entry, String stop, String target, String risk) {
    return 'Entry $entry · Stop $stop · Target $target$risk';
  }

  @override
  String get chartObjectLockedBody => 'Let the finger move it again';

  @override
  String get chartObjectUnlockedBody => 'Hold it exactly where it is';

  @override
  String get chartHideBody => 'Clear it off the chart, keep the idea';

  @override
  String chartObjectsOnChart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objects on this chart',
      one: '1 object on this chart',
    );
    return '$_temp0';
  }

  @override
  String get chartObjectHidden => 'Object hidden.';

  @override
  String get chartUndoAction => 'Undo';

  @override
  String get chartWorkspace => 'WORKSPACE';

  @override
  String get chartToolsLabel => 'TOOLS';

  @override
  String get chartNoLayoutSaved =>
      'No layout saved yet — Save keeps this chart exactly as it looks.';

  @override
  String chartLayoutName(String name) {
    return 'Layout: $name';
  }

  @override
  String get chartLayouts => 'Layouts';

  @override
  String chartLayoutsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved',
      one: '1 saved',
    );
    return '$_temp0';
  }

  @override
  String get chartSettings => 'Settings';

  @override
  String get chartSaveShort => 'Save';

  @override
  String get chartThisChart => 'This chart';

  @override
  String get chartOpen => 'Open';

  @override
  String get chartFromLibrary => 'From library';

  @override
  String get chartNew => 'New';

  @override
  String get chartBlankChart => 'Blank chart';

  @override
  String get chartType => 'Type';

  @override
  String get chartIndicators => 'Indicators';

  @override
  String get chartNone => 'None';

  @override
  String chartStudiesOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count on',
      one: '1 on',
    );
    return '$_temp0';
  }

  @override
  String get chartAlerts => 'Alerts';

  @override
  String get chartLevelTouches => 'Level touches';

  @override
  String get chartReplay => 'Replay';

  @override
  String chartObjectsShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objects',
      one: '1 object',
    );
    return '$_temp0';
  }

  @override
  String get chartTimeZone => 'Time zone';

  @override
  String get chartEvents => 'Events';

  @override
  String get chartSaveLayoutTitle => 'Save layout';

  @override
  String get chartUpdateLayoutTitle => 'Update layout';

  @override
  String get chartLayoutNameLabel => 'Layout name';

  @override
  String get chartSave => 'Save';

  @override
  String get chartUpdate => 'Update';

  @override
  String chartSavedName(String name) {
    return 'Saved “$name”.';
  }

  @override
  String chartOpenedLayout(String name) {
    return 'Opened “$name”.';
  }

  @override
  String chartOpenedLayoutOn(String name, String symbol) {
    return 'Opened “$name” on $symbol — the palette and candle size came with it.';
  }

  @override
  String get chartA11yQuickActions => 'Quick actions at this price';

  @override
  String get chartA11yFitScale => 'Fit the price scale';

  @override
  String get chartA11yFinishDrawing => 'Finish drawing';

  @override
  String get chartTimeZoneTitle => 'Chart time zone';

  @override
  String get chartSearchZone => 'Search a city or zone';

  @override
  String get lockMt5Title => 'MT5 lock';

  @override
  String get lockMt5Body =>
      'Covers MetaTrader 5 on this phone when the stop fires.';

  @override
  String get lockMt5Ready => 'Ready — both permissions granted.';

  @override
  String get lockMt5NeedsA11y => 'Accessibility service not allowed yet';

  @override
  String get lockMt5NeedsOverlay => 'Display over other apps not allowed yet';

  @override
  String get lockMt5Allow => 'Allow';
}
