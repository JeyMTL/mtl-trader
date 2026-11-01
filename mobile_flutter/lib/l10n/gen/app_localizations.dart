import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MTL Trader'**
  String get appTitle;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @navDesk.
  ///
  /// In en, this message translates to:
  /// **'Desk'**
  String get navDesk;

  /// No description provided for @navJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get navJournal;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get navCalendar;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @newTrade.
  ///
  /// In en, this message translates to:
  /// **'Journal a trade'**
  String get newTrade;

  /// No description provided for @timeEdge.
  ///
  /// In en, this message translates to:
  /// **'Time edge'**
  String get timeEdge;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'MTL Trader'**
  String get brandName;

  /// No description provided for @brandOpenPlans.
  ///
  /// In en, this message translates to:
  /// **'MTL Trader — open payment plans'**
  String get brandOpenPlans;

  /// No description provided for @loginHeadline.
  ///
  /// In en, this message translates to:
  /// **'The journal that\nreads you back.'**
  String get loginHeadline;

  /// No description provided for @loginTagline.
  ///
  /// In en, this message translates to:
  /// **'Log the fill, the screenshot and the voice note. Find the hours that pay.'**
  String get loginTagline;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get emailHint;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailInvalid;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters.'**
  String get passwordTooShort;

  /// No description provided for @loginFootnote.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in needs no email confirmation. Email sign-ups must confirm the address before the journal opens.'**
  String get loginFootnote;

  /// No description provided for @googleOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open Google sign-in. Check that a browser is available, then try again.'**
  String get googleOpenFailed;

  /// No description provided for @googleTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in timed out. Check your connection and try again.'**
  String get googleTimedOut;

  /// No description provided for @googleStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start Google sign-in. Try again.'**
  String get googleStartFailed;

  /// No description provided for @signInUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the journal. Check your connection and try again.'**
  String get signInUnreachable;

  /// No description provided for @googleFinishNotice.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in with Google, then return here — the journal opens on its own.'**
  String get googleFinishNotice;

  /// No description provided for @confirmEmailNotice.
  ///
  /// In en, this message translates to:
  /// **'Account created. Open the confirmation link in {email}, then sign in here.'**
  String confirmEmailNotice(String email);

  /// No description provided for @accountBalance.
  ///
  /// In en, this message translates to:
  /// **'Account balance'**
  String get accountBalance;

  /// No description provided for @inProfit.
  ///
  /// In en, this message translates to:
  /// **'In profit'**
  String get inProfit;

  /// No description provided for @inDrawdown.
  ///
  /// In en, this message translates to:
  /// **'In drawdown'**
  String get inDrawdown;

  /// No description provided for @deposits.
  ///
  /// In en, this message translates to:
  /// **'Deposits'**
  String get deposits;

  /// No description provided for @bestTrade.
  ///
  /// In en, this message translates to:
  /// **'Best trade'**
  String get bestTrade;

  /// No description provided for @worstTrade.
  ///
  /// In en, this message translates to:
  /// **'Worst trade'**
  String get worstTrade;

  /// No description provided for @netSummary.
  ///
  /// In en, this message translates to:
  /// **'{pnl} net · {closed} closed · {wins}W / {losses}L'**
  String netSummary(String pnl, int closed, int wins, int losses);

  /// No description provided for @importHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Import history to plot the curve'**
  String get importHistoryHint;

  /// No description provided for @winRate.
  ///
  /// In en, this message translates to:
  /// **'Win rate'**
  String get winRate;

  /// No description provided for @profitFactor.
  ///
  /// In en, this message translates to:
  /// **'Profit factor'**
  String get profitFactor;

  /// No description provided for @maxDrawdown.
  ///
  /// In en, this message translates to:
  /// **'Max drawdown'**
  String get maxDrawdown;

  /// No description provided for @avgPerTrade.
  ///
  /// In en, this message translates to:
  /// **'Avg / trade'**
  String get avgPerTrade;

  /// No description provided for @winnersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} winners'**
  String winnersCount(int count);

  /// No description provided for @peakToTrough.
  ///
  /// In en, this message translates to:
  /// **'Peak to trough'**
  String get peakToTrough;

  /// No description provided for @expectancy.
  ///
  /// In en, this message translates to:
  /// **'Expectancy'**
  String get expectancy;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @monthTrades.
  ///
  /// In en, this message translates to:
  /// **'{count} trades'**
  String monthTrades(int count);

  /// No description provided for @greenDays.
  ///
  /// In en, this message translates to:
  /// **'{count} green days'**
  String greenDays(int count);

  /// No description provided for @monthWinRate.
  ///
  /// In en, this message translates to:
  /// **'Month win rate'**
  String get monthWinRate;

  /// No description provided for @timeEdgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Entry hours in {timezone}; sessions in UTC. Median hold {hold}.'**
  String timeEdgeSubtitle(String timezone, String hold);

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @noTimedTradesTitle.
  ///
  /// In en, this message translates to:
  /// **'No timed trades yet'**
  String get noTimedTradesTitle;

  /// No description provided for @noTimedTradesBody.
  ///
  /// In en, this message translates to:
  /// **'Set the entry and exit time on a trade. The hour and session report builds itself from that window.'**
  String get noTimedTradesBody;

  /// No description provided for @mostProfitableHour.
  ///
  /// In en, this message translates to:
  /// **'Most profitable hour'**
  String get mostProfitableHour;

  /// No description provided for @mostLosses.
  ///
  /// In en, this message translates to:
  /// **'Most losses'**
  String get mostLosses;

  /// No description provided for @bestSession.
  ///
  /// In en, this message translates to:
  /// **'Best session'**
  String get bestSession;

  /// No description provided for @weakestSession.
  ///
  /// In en, this message translates to:
  /// **'Weakest session'**
  String get weakestSession;

  /// No description provided for @needsMoreTrades.
  ///
  /// In en, this message translates to:
  /// **'Needs 3+ trades'**
  String get needsMoreTrades;

  /// No description provided for @periodStats.
  ///
  /// In en, this message translates to:
  /// **'{trades} trades · {winRate} win'**
  String periodStats(int trades, String winRate);

  /// No description provided for @thinSampleNote.
  ///
  /// In en, this message translates to:
  /// **'Hours with fewer than 3 trades are left out of the best/worst call.'**
  String get thinSampleNote;

  /// No description provided for @journalSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalSectionTitle;

  /// No description provided for @journalSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The notes, screenshots and voice notes behind the fills.'**
  String get journalSectionSubtitle;

  /// No description provided for @nothingJournaledTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing journaled yet'**
  String get nothingJournaledTitle;

  /// No description provided for @nothingJournaledBody.
  ///
  /// In en, this message translates to:
  /// **'Open a trade and add a screenshot or a voice note — it becomes the entry you read later.'**
  String get nothingJournaledBody;

  /// No description provided for @recentFills.
  ///
  /// In en, this message translates to:
  /// **'Recent fills'**
  String get recentFills;

  /// No description provided for @noFillsTitle.
  ///
  /// In en, this message translates to:
  /// **'No fills recorded'**
  String get noFillsTitle;

  /// No description provided for @startHere.
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get startHere;

  /// No description provided for @startHeadline.
  ///
  /// In en, this message translates to:
  /// **'Three steps to a journal that pays you back.'**
  String get startHeadline;

  /// No description provided for @startStep1.
  ///
  /// In en, this message translates to:
  /// **'Import MT5 history or log your first fill.'**
  String get startStep1;

  /// No description provided for @startStep2.
  ///
  /// In en, this message translates to:
  /// **'Add the entry and exit time — that powers the edge report.'**
  String get startStep2;

  /// No description provided for @startStep3.
  ///
  /// In en, this message translates to:
  /// **'Attach the chart screenshot and a voice note.'**
  String get startStep3;

  /// No description provided for @seeTimeReport.
  ///
  /// In en, this message translates to:
  /// **'See the time report →'**
  String get seeTimeReport;

  /// No description provided for @couldNotLoadDesk.
  ///
  /// In en, this message translates to:
  /// **'Could not load the desk'**
  String get couldNotLoadDesk;

  /// No description provided for @a11yProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit of {amount}'**
  String a11yProfit(String amount);

  /// No description provided for @a11yLoss.
  ///
  /// In en, this message translates to:
  /// **'Loss of {amount}'**
  String a11yLoss(String amount);

  /// No description provided for @a11yBreakEven.
  ///
  /// In en, this message translates to:
  /// **'Break even, {amount}'**
  String a11yBreakEven(String amount);

  /// No description provided for @a11yEquityCurve.
  ///
  /// In en, this message translates to:
  /// **'Equity curve. {change} since the first recorded day.'**
  String a11yEquityCurve(String change);

  /// No description provided for @a11yHourChart.
  ///
  /// In en, this message translates to:
  /// **'Profit and loss by entry hour.'**
  String get a11yHourChart;

  /// No description provided for @a11yScreenshots.
  ///
  /// In en, this message translates to:
  /// **'{count} screenshots attached'**
  String a11yScreenshots(int count);

  /// No description provided for @a11yVoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'{count} voice notes attached'**
  String a11yVoiceNotes(int count);

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App labels, month names and dates follow this choice. Saved on this phone.'**
  String get languageSubtitle;

  /// No description provided for @journalTitle.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalTitle;

  /// No description provided for @journalSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search symbol, strategy or tag'**
  String get journalSearchHint;

  /// No description provided for @journalSessionAll.
  ///
  /// In en, this message translates to:
  /// **'All sessions'**
  String get journalSessionAll;

  /// No description provided for @journalSessionAsian.
  ///
  /// In en, this message translates to:
  /// **'Asian'**
  String get journalSessionAsian;

  /// No description provided for @journalSessionLondon.
  ///
  /// In en, this message translates to:
  /// **'London'**
  String get journalSessionLondon;

  /// No description provided for @journalSessionNewYork.
  ///
  /// In en, this message translates to:
  /// **'New York'**
  String get journalSessionNewYork;

  /// No description provided for @journalSessionSydney.
  ///
  /// In en, this message translates to:
  /// **'Sydney'**
  String get journalSessionSydney;

  /// No description provided for @journalFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get journalFilterAll;

  /// No description provided for @journalFilterWins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get journalFilterWins;

  /// No description provided for @journalFilterLosses.
  ///
  /// In en, this message translates to:
  /// **'Losses'**
  String get journalFilterLosses;

  /// No description provided for @journalLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get journalLoading;

  /// No description provided for @journalCountSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} trades · {pnl}'**
  String journalCountSummary(int count, String pnl);

  /// No description provided for @journalLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get journalLoadMore;

  /// No description provided for @journalClearMenu.
  ///
  /// In en, this message translates to:
  /// **'Clear journal'**
  String get journalClearMenu;

  /// No description provided for @journalEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No trades found'**
  String get journalEmptyTitle;

  /// No description provided for @journalEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap + to journal a fill, or import your MT5 history on the web desk.'**
  String get journalEmptyBody;

  /// No description provided for @journalErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load the journal'**
  String get journalErrorTitle;

  /// No description provided for @deleteTradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this trade?'**
  String get deleteTradeTitle;

  /// No description provided for @deleteTradeBody.
  ///
  /// In en, this message translates to:
  /// **'{symbol} and its photos or voice notes will be removed. This cannot be undone.'**
  String deleteTradeBody(String symbol);

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @deleteDone.
  ///
  /// In en, this message translates to:
  /// **'Trade deleted.'**
  String get deleteDone;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the trade: {error}'**
  String deleteFailed(String error);

  /// No description provided for @clearJournalTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the journal?'**
  String get clearJournalTitle;

  /// No description provided for @clearJournalBody.
  ///
  /// In en, this message translates to:
  /// **'Every trade, photo and voice note in this account is removed. This cannot be undone.'**
  String get clearJournalBody;

  /// No description provided for @clearAllAction.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAllAction;

  /// No description provided for @clearFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the journal: {error}'**
  String clearFailed(String error);

  /// No description provided for @analyticsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No trades to analyse yet'**
  String get analyticsEmptyTitle;

  /// No description provided for @analyticsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Journal a few entries and the breakdowns fill in automatically.'**
  String get analyticsEmptyBody;

  /// No description provided for @analyticsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load analytics'**
  String get analyticsErrorTitle;

  /// No description provided for @analyticsErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get analyticsErrorBody;

  /// No description provided for @timeEdgeDescription.
  ///
  /// In en, this message translates to:
  /// **'Best and worst entry hour, sessions and the 24-hour curve.'**
  String get timeEdgeDescription;

  /// No description provided for @performanceSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Performance summary'**
  String get performanceSummaryTitle;

  /// No description provided for @performanceSummarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every closed trade in your journal.'**
  String get performanceSummarySubtitle;

  /// No description provided for @summaryTrades.
  ///
  /// In en, this message translates to:
  /// **'Trades'**
  String get summaryTrades;

  /// No description provided for @summaryTradesFoot.
  ///
  /// In en, this message translates to:
  /// **'{count} this month'**
  String summaryTradesFoot(int count);

  /// No description provided for @summaryWinLoss.
  ///
  /// In en, this message translates to:
  /// **'{wins}W · {losses}L'**
  String summaryWinLoss(int wins, int losses);

  /// No description provided for @summaryGrossFoot.
  ///
  /// In en, this message translates to:
  /// **'Gross {profit} / {loss}'**
  String summaryGrossFoot(String profit, String loss);

  /// No description provided for @summaryAverageTrade.
  ///
  /// In en, this message translates to:
  /// **'Average trade'**
  String get summaryAverageTrade;

  /// No description provided for @summaryNetFoot.
  ///
  /// In en, this message translates to:
  /// **'Net {net}'**
  String summaryNetFoot(String net);

  /// No description provided for @summaryBestTradeFoot.
  ///
  /// In en, this message translates to:
  /// **'Worst {worst}'**
  String summaryBestTradeFoot(String worst);

  /// No description provided for @summaryMonthFoot.
  ///
  /// In en, this message translates to:
  /// **'{count} winning days'**
  String summaryMonthFoot(int count);

  /// No description provided for @monthlyPnlTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly P&L'**
  String get monthlyPnlTitle;

  /// No description provided for @monthlyPnlSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Last six months'**
  String get monthlyPnlSubtitle;

  /// No description provided for @pnlByDayTitle.
  ///
  /// In en, this message translates to:
  /// **'P&L by day'**
  String get pnlByDayTitle;

  /// No description provided for @pnlByDayRecent.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get pnlByDayRecent;

  /// No description provided for @pnlByDayBestWorst.
  ///
  /// In en, this message translates to:
  /// **'Best {bestDay} {bestPnl} · Worst {worstDay} {worstPnl}'**
  String pnlByDayBestWorst(
      String bestDay, String bestPnl, String worstDay, String worstPnl);

  /// No description provided for @legendLoss.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get legendLoss;

  /// No description provided for @legendNoTrades.
  ///
  /// In en, this message translates to:
  /// **'No trades'**
  String get legendNoTrades;

  /// No description provided for @legendProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get legendProfit;

  /// No description provided for @tapADay.
  ///
  /// In en, this message translates to:
  /// **'Tap a day'**
  String get tapADay;

  /// No description provided for @performanceBySymbol.
  ///
  /// In en, this message translates to:
  /// **'Performance by symbol'**
  String get performanceBySymbol;

  /// No description provided for @performanceBySymbolSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sorted by net P&L'**
  String get performanceBySymbolSubtitle;

  /// No description provided for @performanceByTag.
  ///
  /// In en, this message translates to:
  /// **'Performance by tag'**
  String get performanceByTag;

  /// No description provided for @performanceByTagSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tags you add to a trade, rolled up.'**
  String get performanceByTagSubtitle;

  /// No description provided for @symbolStats.
  ///
  /// In en, this message translates to:
  /// **'{trades}T · {winRate} win'**
  String symbolStats(int trades, String winRate);

  /// No description provided for @tagStats.
  ///
  /// In en, this message translates to:
  /// **'{trades}T · {wins}W {losses}L · {winRate}'**
  String tagStats(int trades, int wins, int losses, String winRate);

  /// No description provided for @a11yRunningCurve.
  ///
  /// In en, this message translates to:
  /// **'Running profit and loss for the last 30 days.'**
  String get a11yRunningCurve;

  /// No description provided for @a11yHeatmapDay.
  ///
  /// In en, this message translates to:
  /// **'{day}: {pnl}, {trades} trades'**
  String a11yHeatmapDay(String day, String pnl, int trades);

  /// No description provided for @a11yHeatmapEmpty.
  ///
  /// In en, this message translates to:
  /// **'{day}: no trades'**
  String a11yHeatmapEmpty(String day);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
