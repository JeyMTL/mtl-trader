import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MTL Ledger'**
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

  /// No description provided for @languageSystemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow the device language'**
  String get languageSystemSubtitle;

  /// No description provided for @searchLanguages.
  ///
  /// In en, this message translates to:
  /// **'Search languages'**
  String get searchLanguages;

  /// No description provided for @noLanguageMatches.
  ///
  /// In en, this message translates to:
  /// **'No language matches that search.'**
  String get noLanguageMatches;

  /// No description provided for @languageBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get languageBuiltIn;

  /// No description provided for @languageDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get languageDownload;

  /// No description provided for @languageDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get languageDownloading;

  /// No description provided for @languageDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get languageDownloaded;

  /// No description provided for @languageRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove download'**
  String get languageRemove;

  /// No description provided for @languageEnglishFallback.
  ///
  /// In en, this message translates to:
  /// **'English until translated'**
  String get languageEnglishFallback;

  /// No description provided for @languagePackFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download this language. Check your connection and try again.'**
  String get languagePackFailed;

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
  /// **'MTL Ledger'**
  String get brandName;

  /// No description provided for @brandOpenPlans.
  ///
  /// In en, this message translates to:
  /// **'MTL Ledger — open payment plans'**
  String get brandOpenPlans;

  /// No description provided for @upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgrade;

  /// No description provided for @rules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rules;

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
  /// **'{count, plural, =1{1 winner} other{{count} winners}}'**
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
  /// **'{count, plural, =1{1 trade} other{{count} trades}}'**
  String monthTrades(int count);

  /// No description provided for @greenDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 green day} other{{count} green days}}'**
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
  /// **'{trades, plural, =1{1 trade} other{{trades} trades}} · {winRate} win'**
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
  /// **'{count, plural, =1{1 screenshot attached} other{{count} screenshots attached}}'**
  String a11yScreenshots(int count);

  /// No description provided for @a11yVoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 voice note attached} other{{count} voice notes attached}}'**
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
  /// **'{count, plural, =1{1 trade} other{{count} trades}} · {pnl}'**
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
  /// **'{count, plural, =1{1 winning day} other{{count} winning days}}'**
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
  /// **'{day}: {pnl}, {trades, plural, =1{1 trade} other{{trades} trades}}'**
  String a11yHeatmapDay(String day, String pnl, int trades);

  /// No description provided for @a11yHeatmapEmpty.
  ///
  /// In en, this message translates to:
  /// **'{day}: no trades'**
  String a11yHeatmapEmpty(String day);

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @accountSignOutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get accountSignOutQuestion;

  /// No description provided for @accountSignOutBody.
  ///
  /// In en, this message translates to:
  /// **'Your journal stays on the server. Sign back in any time.'**
  String get accountSignOutBody;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @accountPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get accountPlan;

  /// No description provided for @accountStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get accountStatus;

  /// No description provided for @accountTradeLimit.
  ///
  /// In en, this message translates to:
  /// **'Trade limit / month'**
  String get accountTradeLimit;

  /// No description provided for @accountUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get accountUnlimited;

  /// No description provided for @accountTimezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get accountTimezone;

  /// No description provided for @accountChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get accountChange;

  /// No description provided for @accountTrialEnds.
  ///
  /// In en, this message translates to:
  /// **'Trial ends'**
  String get accountTrialEnds;

  /// No description provided for @accountAccessUntil.
  ///
  /// In en, this message translates to:
  /// **'Access until'**
  String get accountAccessUntil;

  /// No description provided for @accountPaidThrough.
  ///
  /// In en, this message translates to:
  /// **'Paid through'**
  String get accountPaidThrough;

  /// No description provided for @accountViewPlans.
  ///
  /// In en, this message translates to:
  /// **'View plans & billing'**
  String get accountViewPlans;

  /// No description provided for @accountBuyPlan.
  ///
  /// In en, this message translates to:
  /// **'Buy a subscription'**
  String get accountBuyPlan;

  /// No description provided for @accountSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get accountSubscription;

  /// No description provided for @accountSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get accountSignedIn;

  /// No description provided for @accountSubError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your subscription'**
  String get accountSubError;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @sectionTrading.
  ///
  /// In en, this message translates to:
  /// **'Trading'**
  String get sectionTrading;

  /// No description provided for @sectionPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get sectionPreferences;

  /// No description provided for @sectionSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get sectionSupport;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @accountAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get accountAppearance;

  /// No description provided for @accountAppearanceBody.
  ///
  /// In en, this message translates to:
  /// **'Dark, light, the mark\'s blue, or follow the device. Saved on this phone.'**
  String get accountAppearanceBody;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get themeBlue;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @accountHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & feedback'**
  String get accountHelp;

  /// No description provided for @accountHelpBody.
  ///
  /// In en, this message translates to:
  /// **'Questions, bugs, or something the journal should do. Every message is read.'**
  String get accountHelpBody;

  /// No description provided for @accountEmailSupport.
  ///
  /// In en, this message translates to:
  /// **'Email support'**
  String get accountEmailSupport;

  /// No description provided for @accountRate.
  ///
  /// In en, this message translates to:
  /// **'Rate MTL Ledger'**
  String get accountRate;

  /// No description provided for @accountAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get accountAbout;

  /// No description provided for @accountAboutBody.
  ///
  /// In en, this message translates to:
  /// **'Where your journal media lives.'**
  String get accountAboutBody;

  /// No description provided for @accountPrivateMedia.
  ///
  /// In en, this message translates to:
  /// **'Private media'**
  String get accountPrivateMedia;

  /// No description provided for @accountPrivateMediaBody.
  ///
  /// In en, this message translates to:
  /// **'Journal photos and voice notes live in a private bucket. Each file is signed for one hour and only your account can request it.'**
  String get accountPrivateMediaBody;

  /// No description provided for @accountFooter.
  ///
  /// In en, this message translates to:
  /// **'MTL Ledger · flat mobile journal\nTrades, notes and media stay on your Supabase project.'**
  String get accountFooter;

  /// No description provided for @accountRules.
  ///
  /// In en, this message translates to:
  /// **'Rules & playbook'**
  String get accountRules;

  /// No description provided for @accountConnectMt5.
  ///
  /// In en, this message translates to:
  /// **'Connect MT5 account'**
  String get accountConnectMt5;

  /// No description provided for @accountImport.
  ///
  /// In en, this message translates to:
  /// **'Import trade history'**
  String get accountImport;

  /// No description provided for @accountBacktest.
  ///
  /// In en, this message translates to:
  /// **'Backtester (Pro)'**
  String get accountBacktest;

  /// No description provided for @accountPropFirm.
  ///
  /// In en, this message translates to:
  /// **'Prop firm simulation'**
  String get accountPropFirm;

  /// No description provided for @accountTimezoneRow.
  ///
  /// In en, this message translates to:
  /// **'Report timezone'**
  String get accountTimezoneRow;

  /// No description provided for @accountTimezoneDialog.
  ///
  /// In en, this message translates to:
  /// **'Timezone for the hour report'**
  String get accountTimezoneDialog;

  /// No description provided for @accountTimezoneSaved.
  ///
  /// In en, this message translates to:
  /// **'Hour report now uses {zone}.'**
  String accountTimezoneSaved(String zone);

  /// No description provided for @accountTimezoneFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the timezone: {error}'**
  String accountTimezoneFailed(String error);

  /// No description provided for @accountPicture.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get accountPicture;

  /// No description provided for @accountPictureBody.
  ///
  /// In en, this message translates to:
  /// **'Paste a link to an image. Leave it empty to use the picture tied to your email, or your initials when there is none.'**
  String get accountPictureBody;

  /// No description provided for @accountPictureCleared.
  ///
  /// In en, this message translates to:
  /// **'Profile picture cleared.'**
  String get accountPictureCleared;

  /// No description provided for @accountPictureUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile picture updated.'**
  String get accountPictureUpdated;

  /// No description provided for @accountPictureFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the picture: {error}'**
  String accountPictureFailed(String error);

  /// No description provided for @accountStoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the store listing.'**
  String get accountStoreFailed;

  /// No description provided for @accountMailFailed.
  ///
  /// In en, this message translates to:
  /// **'No mail app was found. Install one and tap the button again.'**
  String get accountMailFailed;

  /// No description provided for @accountDailyStop.
  ///
  /// In en, this message translates to:
  /// **'Daily stop'**
  String get accountDailyStop;

  /// No description provided for @accountDailyStopBody.
  ///
  /// In en, this message translates to:
  /// **'What happens when the loss budget or entry cap is reached.'**
  String get accountDailyStopBody;

  /// No description provided for @accountLossBudget.
  ///
  /// In en, this message translates to:
  /// **'Loss budget'**
  String get accountLossBudget;

  /// No description provided for @accountMaxEntries.
  ///
  /// In en, this message translates to:
  /// **'Max entries'**
  String get accountMaxEntries;

  /// No description provided for @accountWhenReached.
  ///
  /// In en, this message translates to:
  /// **'When reached'**
  String get accountWhenReached;

  /// No description provided for @accountOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get accountOff;

  /// No description provided for @accountNoCap.
  ///
  /// In en, this message translates to:
  /// **'No cap'**
  String get accountNoCap;

  /// No description provided for @accountLoadingRules.
  ///
  /// In en, this message translates to:
  /// **'Loading your rules…'**
  String get accountLoadingRules;

  /// No description provided for @accountEditRules.
  ///
  /// In en, this message translates to:
  /// **'Edit rules and daily stop'**
  String get accountEditRules;

  /// No description provided for @lockSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft lock'**
  String get lockSoft;

  /// No description provided for @lockHard.
  ///
  /// In en, this message translates to:
  /// **'Hard lock'**
  String get lockHard;

  /// No description provided for @lockJournalOnly.
  ///
  /// In en, this message translates to:
  /// **'Journal only'**
  String get lockJournalOnly;

  /// No description provided for @accountStopNone.
  ///
  /// In en, this message translates to:
  /// **'No stop is set yet. Add a loss budget or an entry cap and the day ends when it is reached.'**
  String get accountStopNone;

  /// No description provided for @accountStopSoft.
  ///
  /// In en, this message translates to:
  /// **'After the stop, MetaTrader 5 on this phone is covered and the journal stays open. Reset from the banner.'**
  String get accountStopSoft;

  /// No description provided for @accountStopHard.
  ///
  /// In en, this message translates to:
  /// **'After the stop, the journal locks and the MT5 guard removes resting orders and closes any position opened after it. It clears at the start of your next trading day — a hard stop cannot be lifted.'**
  String get accountStopHard;

  /// No description provided for @accountStopOff.
  ///
  /// In en, this message translates to:
  /// **'After the stop, the journal refuses new entries until the next trading day.'**
  String get accountStopOff;

  /// No description provided for @rulesIntro.
  ///
  /// In en, this message translates to:
  /// **'The checklist you trade by, the days and sessions it applies to, and the stop that ends the day.'**
  String get rulesIntro;

  /// No description provided for @rulesYourRules.
  ///
  /// In en, this message translates to:
  /// **'Your rules'**
  String get rulesYourRules;

  /// No description provided for @rulesYourRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Write them as instructions to yourself: what must be true before entry, what invalidates the trade, and what ends your session.'**
  String get rulesYourRulesBody;

  /// No description provided for @rulesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rules yet. The first one is usually the hardest to keep.'**
  String get rulesEmpty;

  /// No description provided for @rulesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get rulesAdd;

  /// No description provided for @rulesRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove rule'**
  String get rulesRemove;

  /// No description provided for @rulesDays.
  ///
  /// In en, this message translates to:
  /// **'Days you trade'**
  String get rulesDays;

  /// No description provided for @rulesDaysBody.
  ///
  /// In en, this message translates to:
  /// **'Reminders only fire on these days. Trading outside them is usually the leak.'**
  String get rulesDaysBody;

  /// No description provided for @rulesDailyStop.
  ///
  /// In en, this message translates to:
  /// **'Daily stop'**
  String get rulesDailyStop;

  /// No description provided for @rulesDailyStopBody.
  ///
  /// In en, this message translates to:
  /// **'The loss budget and entry cap you commit to before the session. Leave both at 0 to switch the stop off.'**
  String get rulesDailyStopBody;

  /// No description provided for @rulesLossBudget.
  ///
  /// In en, this message translates to:
  /// **'Loss budget'**
  String get rulesLossBudget;

  /// No description provided for @rulesMaxEntries.
  ///
  /// In en, this message translates to:
  /// **'Max entries'**
  String get rulesMaxEntries;

  /// No description provided for @rulesWhenReached.
  ///
  /// In en, this message translates to:
  /// **'When the stop is reached'**
  String get rulesWhenReached;

  /// No description provided for @rulesJournalOnlyBlurb.
  ///
  /// In en, this message translates to:
  /// **'New entries are refused in the app.'**
  String get rulesJournalOnlyBlurb;

  /// No description provided for @rulesSoftBlurb.
  ///
  /// In en, this message translates to:
  /// **'MT5 is covered on this phone. The journal stays open.'**
  String get rulesSoftBlurb;

  /// No description provided for @rulesHardBlurb.
  ///
  /// In en, this message translates to:
  /// **'The journal locks and the MT5 guard removes resting orders until tomorrow. No reset.'**
  String get rulesHardBlurb;

  /// No description provided for @rulesSessions.
  ///
  /// In en, this message translates to:
  /// **'Trading sessions'**
  String get rulesSessions;

  /// No description provided for @rulesSessionsBody.
  ///
  /// In en, this message translates to:
  /// **'The windows you actually sit down for. A session that ends before it starts is treated as overnight.'**
  String get rulesSessionsBody;

  /// No description provided for @rulesNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet. Add the window you trade in.'**
  String get rulesNoSessions;

  /// No description provided for @rulesSessionName.
  ///
  /// In en, this message translates to:
  /// **'Session name'**
  String get rulesSessionName;

  /// No description provided for @rulesRemoveSession.
  ///
  /// In en, this message translates to:
  /// **'Remove session'**
  String get rulesRemoveSession;

  /// No description provided for @rulesAddSession.
  ///
  /// In en, this message translates to:
  /// **'Add session'**
  String get rulesAddSession;

  /// No description provided for @rulesNewSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get rulesNewSession;

  /// No description provided for @rulesSessionFallback.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get rulesSessionFallback;

  /// No description provided for @rulesReminders.
  ///
  /// In en, this message translates to:
  /// **'Remind me before a session'**
  String get rulesReminders;

  /// No description provided for @rulesRemindersBody.
  ///
  /// In en, this message translates to:
  /// **'An in-app reminder with your rules in front of you, before the first trade.'**
  String get rulesRemindersBody;

  /// No description provided for @rulesRemindersOn.
  ///
  /// In en, this message translates to:
  /// **'Reminders on'**
  String get rulesRemindersOn;

  /// No description provided for @rulesRemindersOff.
  ///
  /// In en, this message translates to:
  /// **'Reminders off'**
  String get rulesRemindersOff;

  /// No description provided for @rulesReminderLead.
  ///
  /// In en, this message translates to:
  /// **'How long before'**
  String get rulesReminderLead;

  /// No description provided for @rulesReminderMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String rulesReminderMinutes(String minutes);

  /// No description provided for @rulesNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes for yourself'**
  String get rulesNotes;

  /// No description provided for @rulesNotesHint.
  ///
  /// In en, this message translates to:
  /// **'What usually goes wrong, and what you do about it.'**
  String get rulesNotesHint;

  /// No description provided for @rulesSave.
  ///
  /// In en, this message translates to:
  /// **'Save rules'**
  String get rulesSave;

  /// No description provided for @rulesSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get rulesSaving;

  /// No description provided for @rulesSaved.
  ///
  /// In en, this message translates to:
  /// **'Rules saved.'**
  String get rulesSaved;

  /// No description provided for @rulesSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your rules: {error}'**
  String rulesSaveError(String error);

  /// No description provided for @rulesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your rules: {error}'**
  String rulesLoadError(String error);

  /// No description provided for @rulesMaxReached.
  ///
  /// In en, this message translates to:
  /// **'A playbook holds 20 rules. Fewer is easier to follow.'**
  String get rulesMaxReached;

  /// No description provided for @rulesSessionsMax.
  ///
  /// In en, this message translates to:
  /// **'Up to 6 sessions.'**
  String get rulesSessionsMax;

  /// No description provided for @lockHardBadge.
  ///
  /// In en, this message translates to:
  /// **'HARD LOCK'**
  String get lockHardBadge;

  /// No description provided for @lockSoftBadge.
  ///
  /// In en, this message translates to:
  /// **'SOFT LOCK'**
  String get lockSoftBadge;

  /// No description provided for @lockDayOver.
  ///
  /// In en, this message translates to:
  /// **'Your day is over'**
  String get lockDayOver;

  /// No description provided for @lockLossBody.
  ///
  /// In en, this message translates to:
  /// **'You reached your loss budget — {used} of {limit}. The journal is closed until the next session.'**
  String lockLossBody(String used, String limit);

  /// No description provided for @lockCapBody.
  ///
  /// In en, this message translates to:
  /// **'You reached your entry cap — {trades} of {max} entries. The journal is closed until the next session.'**
  String lockCapBody(String trades, String max);

  /// No description provided for @lockRealised.
  ///
  /// In en, this message translates to:
  /// **'REALISED'**
  String get lockRealised;

  /// No description provided for @lockEntries.
  ///
  /// In en, this message translates to:
  /// **'ENTRIES'**
  String get lockEntries;

  /// No description provided for @lockAfterStop.
  ///
  /// In en, this message translates to:
  /// **'AFTER STOP'**
  String get lockAfterStop;

  /// No description provided for @lockResetsNext.
  ///
  /// In en, this message translates to:
  /// **'Resets at the next session'**
  String get lockResetsNext;

  /// No description provided for @lockResetsAt.
  ///
  /// In en, this message translates to:
  /// **'Resets {clock} · {countdown}'**
  String lockResetsAt(String clock, String countdown);

  /// No description provided for @lockHardBody.
  ///
  /// In en, this message translates to:
  /// **'Your MT5 guard removes resting orders while the day is locked and closes any position opened after the stop. It cannot stop a manual market order — only your broker can.'**
  String get lockHardBody;

  /// No description provided for @lockHardBody2.
  ///
  /// In en, this message translates to:
  /// **'A manual market order can still fill before any EA sees it — only the broker can stop that click. There is no release here: the lock clears at the start of your next trading day.'**
  String get lockHardBody2;

  /// No description provided for @lockUnfreezeToday.
  ///
  /// In en, this message translates to:
  /// **'Lift the stop'**
  String get lockUnfreezeToday;

  /// No description provided for @lockUnfreezing.
  ///
  /// In en, this message translates to:
  /// **'Lifting…'**
  String get lockUnfreezing;

  /// No description provided for @lockGreenDay.
  ///
  /// In en, this message translates to:
  /// **'Reaching the stop is a green day. The trades you took before it are already in your journal.'**
  String get lockGreenDay;

  /// No description provided for @lockStopReached.
  ///
  /// In en, this message translates to:
  /// **'Your daily stop is reached.'**
  String get lockStopReached;

  /// No description provided for @lockBudgetMessage.
  ///
  /// In en, this message translates to:
  /// **'Daily loss budget reached: {used} of {limit}.'**
  String lockBudgetMessage(String used, String limit);

  /// No description provided for @lockSoftReached.
  ///
  /// In en, this message translates to:
  /// **'The daily stop is reached · the journal stays open'**
  String get lockSoftReached;

  /// No description provided for @lockSoftFrozen.
  ///
  /// In en, this message translates to:
  /// **'Soft lock · guard active'**
  String get lockSoftFrozen;

  /// No description provided for @lockFreezerOff.
  ///
  /// In en, this message translates to:
  /// **'Freezer is off — tap to turn it on'**
  String get lockFreezerOff;

  /// No description provided for @lockUnfreeze.
  ///
  /// In en, this message translates to:
  /// **'Lift the stop'**
  String get lockUnfreeze;

  /// No description provided for @lockA11yService.
  ///
  /// In en, this message translates to:
  /// **'Accessibility service'**
  String get lockA11yService;

  /// No description provided for @lockA11yServiceBody.
  ///
  /// In en, this message translates to:
  /// **'Android shows MTL Ledger which app is in front. It never reads what is on the screen, and nothing is sent off the phone.'**
  String get lockA11yServiceBody;

  /// No description provided for @lockOverlay.
  ///
  /// In en, this message translates to:
  /// **'Display over other apps'**
  String get lockOverlay;

  /// No description provided for @lockOverlayBody.
  ///
  /// In en, this message translates to:
  /// **'Lets the journal draw the cover on top of MetaTrader 5 while the day is frozen. No other app is covered.'**
  String get lockOverlayBody;

  /// No description provided for @lockInControl.
  ///
  /// In en, this message translates to:
  /// **'You stay in control'**
  String get lockInControl;

  /// No description provided for @lockInControlBody.
  ///
  /// In en, this message translates to:
  /// **'Both switches live in Android Settings and can be turned off at any time. The journal keeps working without them.'**
  String get lockInControlBody;

  /// No description provided for @lockFreezerTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on the MT5 freezer?'**
  String get lockFreezerTitle;

  /// No description provided for @lockFreezerBody.
  ///
  /// In en, this message translates to:
  /// **'The freezer needs two Android permissions before it can cover MetaTrader 5 after your daily stop. Android will ask for each one on the next screen.'**
  String get lockFreezerBody;

  /// No description provided for @lockNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get lockNotNow;

  /// No description provided for @lockAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree'**
  String get lockAgree;

  /// No description provided for @lockDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Lift the stop — once today'**
  String get lockDialogTitle;

  /// No description provided for @lockDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Saving your reason reopens the day, and the guard stops removing orders on its next poll. It is a grace run, not a reset: the stop re-arms on the trades you take after this, with the same budget — lose that too and the day stays closed.'**
  String get lockDialogBody;

  /// No description provided for @lockReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why is trading past the stop worth it today?'**
  String get lockReasonHint;

  /// No description provided for @lockReasonFoot.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters. Your broker is not affected by this button.'**
  String get lockReasonFoot;

  /// No description provided for @lockSoftDetail.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit} · the journal stays open'**
  String lockSoftDetail(String used, String limit);

  /// No description provided for @alertsSection.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alertsSection;

  /// No description provided for @alertsBody.
  ///
  /// In en, this message translates to:
  /// **'On this phone, while the app is open. Nothing is sent anywhere.'**
  String get alertsBody;

  /// No description provided for @alertsDailyStop.
  ///
  /// In en, this message translates to:
  /// **'Daily stop hit'**
  String get alertsDailyStop;

  /// No description provided for @alertsDailyStopBody.
  ///
  /// In en, this message translates to:
  /// **'Tell me when the loss limit is reached and trading locks.'**
  String get alertsDailyStopBody;

  /// No description provided for @alertsLevels.
  ///
  /// In en, this message translates to:
  /// **'Level touched'**
  String get alertsLevels;

  /// No description provided for @alertsLevelsBody.
  ///
  /// In en, this message translates to:
  /// **'Tell me when price crosses a level I drew on a chart.'**
  String get alertsLevelsBody;

  /// No description provided for @alertsJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal reminder'**
  String get alertsJournal;

  /// No description provided for @alertsJournalBody.
  ///
  /// In en, this message translates to:
  /// **'A daily nudge to log the day.'**
  String get alertsJournalBody;

  /// No description provided for @alertsReminderAt.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get alertsReminderAt;

  /// No description provided for @alertsHistory.
  ///
  /// In en, this message translates to:
  /// **'Notification history'**
  String get alertsHistory;

  /// No description provided for @alertsHistoryBody.
  ///
  /// In en, this message translates to:
  /// **'Everything this phone has alerted on, and why it fired.'**
  String get alertsHistoryBody;

  /// No description provided for @alertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alertsTitle;

  /// No description provided for @alertsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing has fired yet'**
  String get alertsEmpty;

  /// No description provided for @alertsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'When a stop hits or a level is touched, the alert appears here with the reason it fired.'**
  String get alertsEmptyBody;

  /// No description provided for @alertsWhy.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get alertsWhy;

  /// No description provided for @alertsNotShown.
  ///
  /// In en, this message translates to:
  /// **'not shown'**
  String get alertsNotShown;

  /// No description provided for @alertsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get alertsClear;

  /// No description provided for @alertsSendTest.
  ///
  /// In en, this message translates to:
  /// **'Send a test alert'**
  String get alertsSendTest;

  /// No description provided for @alertsPermissionMissing.
  ///
  /// In en, this message translates to:
  /// **'Android is not letting this app post notifications. Allow them in system settings.'**
  String get alertsPermissionMissing;

  /// The plan pill on the desk while a free trial is running: the word Trial and the days left.
  ///
  /// In en, this message translates to:
  /// **'Trial · {days}d'**
  String planTrialDays(int days);

  /// No description provided for @tradeNewEntry.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get tradeNewEntry;

  /// No description provided for @tradeEditEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get tradeEditEntry;

  /// No description provided for @tradeSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get tradeSaveChanges;

  /// No description provided for @tradeSaveEntry.
  ///
  /// In en, this message translates to:
  /// **'Save entry'**
  String get tradeSaveEntry;

  /// No description provided for @tradeInstrument.
  ///
  /// In en, this message translates to:
  /// **'Instrument'**
  String get tradeInstrument;

  /// No description provided for @tradeSymbol.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get tradeSymbol;

  /// No description provided for @tradePickInstrument.
  ///
  /// In en, this message translates to:
  /// **'Pick an instrument'**
  String get tradePickInstrument;

  /// No description provided for @tradeSymbolRequired.
  ///
  /// In en, this message translates to:
  /// **'A symbol is required.'**
  String get tradeSymbolRequired;

  /// No description provided for @tradeBuy.
  ///
  /// In en, this message translates to:
  /// **'BUY'**
  String get tradeBuy;

  /// No description provided for @tradeSell.
  ///
  /// In en, this message translates to:
  /// **'SELL'**
  String get tradeSell;

  /// No description provided for @tradePinLevels.
  ///
  /// In en, this message translates to:
  /// **'Pin levels from chart'**
  String get tradePinLevels;

  /// No description provided for @tradeStrategy.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get tradeStrategy;

  /// No description provided for @tradeSavedStrategies.
  ///
  /// In en, this message translates to:
  /// **'Saved strategies'**
  String get tradeSavedStrategies;

  /// No description provided for @tradeSimilarStrategy.
  ///
  /// In en, this message translates to:
  /// **'You already use “{name}”. Pick the existing spelling so its statistics stay together.'**
  String tradeSimilarStrategy(String name);

  /// No description provided for @tradeExecution.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get tradeExecution;

  /// No description provided for @tradePrices.
  ///
  /// In en, this message translates to:
  /// **'Prices'**
  String get tradePrices;

  /// No description provided for @tradeEntryPrice.
  ///
  /// In en, this message translates to:
  /// **'Entry price'**
  String get tradeEntryPrice;

  /// No description provided for @tradeStopTarget.
  ///
  /// In en, this message translates to:
  /// **'Stop & target'**
  String get tradeStopTarget;

  /// No description provided for @tradeStopLoss.
  ///
  /// In en, this message translates to:
  /// **'Stop loss'**
  String get tradeStopLoss;

  /// No description provided for @tradeTakeProfit.
  ///
  /// In en, this message translates to:
  /// **'Take profit'**
  String get tradeTakeProfit;

  /// No description provided for @tradeExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get tradeExit;

  /// No description provided for @tradeSizeCosts.
  ///
  /// In en, this message translates to:
  /// **'Size & costs'**
  String get tradeSizeCosts;

  /// No description provided for @tradeSizeLots.
  ///
  /// In en, this message translates to:
  /// **'Size (lots)'**
  String get tradeSizeLots;

  /// No description provided for @tradeCommission.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get tradeCommission;

  /// No description provided for @tradeSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get tradeSwap;

  /// No description provided for @tradeNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get tradeNotSet;

  /// No description provided for @tradeFoundWithExit.
  ///
  /// In en, this message translates to:
  /// **'Found with the exit'**
  String get tradeFoundWithExit;

  /// No description provided for @tradeNotFoundYet.
  ///
  /// In en, this message translates to:
  /// **'Not found yet'**
  String get tradeNotFoundYet;

  /// No description provided for @tradeExitReadsCandles.
  ///
  /// In en, this message translates to:
  /// **'The app reads the candles after entry and takes whichever of the two levels the market hit first.'**
  String get tradeExitReadsCandles;

  /// No description provided for @tradeFindExit.
  ///
  /// In en, this message translates to:
  /// **'Find exit'**
  String get tradeFindExit;

  /// No description provided for @tradeFindAgain.
  ///
  /// In en, this message translates to:
  /// **'Find again'**
  String get tradeFindAgain;

  /// No description provided for @tradeSavedExit.
  ///
  /// In en, this message translates to:
  /// **'Saved exit'**
  String get tradeSavedExit;

  /// No description provided for @tradeExitTakeProfit.
  ///
  /// In en, this message translates to:
  /// **'Take profit hit first'**
  String get tradeExitTakeProfit;

  /// No description provided for @tradeExitStopLoss.
  ///
  /// In en, this message translates to:
  /// **'Stop loss hit first'**
  String get tradeExitStopLoss;

  /// No description provided for @tradeExitLatestPrice.
  ///
  /// In en, this message translates to:
  /// **'Neither level reached · marked at the latest price'**
  String get tradeExitLatestPrice;

  /// No description provided for @tradeTimeWindow.
  ///
  /// In en, this message translates to:
  /// **'Time window'**
  String get tradeTimeWindow;

  /// No description provided for @tradeTimeWindowSub.
  ///
  /// In en, this message translates to:
  /// **'Entry and exit time drive the hour and session report.'**
  String get tradeTimeWindowSub;

  /// No description provided for @tradeOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get tradeOpened;

  /// No description provided for @tradeClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get tradeClosed;

  /// No description provided for @tradeTimeInMarket.
  ///
  /// In en, this message translates to:
  /// **'Time in market'**
  String get tradeTimeInMarket;

  /// No description provided for @tradeSetBothTimes.
  ///
  /// In en, this message translates to:
  /// **'Set both times'**
  String get tradeSetBothTimes;

  /// No description provided for @tradeExitBeforeEntry.
  ///
  /// In en, this message translates to:
  /// **'Exit before entry'**
  String get tradeExitBeforeEntry;

  /// No description provided for @tradeJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get tradeJournal;

  /// No description provided for @tradeJournalSub.
  ///
  /// In en, this message translates to:
  /// **'What was the setup, and what did you actually do?'**
  String get tradeJournalSub;

  /// No description provided for @tradeJournalHint.
  ///
  /// In en, this message translates to:
  /// **'The idea, the trigger, how you managed it.'**
  String get tradeJournalHint;

  /// No description provided for @tradeMedia.
  ///
  /// In en, this message translates to:
  /// **'Photos & voice notes'**
  String get tradeMedia;

  /// No description provided for @tradeMediaSub.
  ///
  /// In en, this message translates to:
  /// **'A chart screenshot and a spoken note are worth more than a paragraph later.'**
  String get tradeMediaSub;

  /// No description provided for @tradeGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get tradeGallery;

  /// No description provided for @tradeCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get tradeCamera;

  /// No description provided for @tradeRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get tradeRecord;

  /// No description provided for @tradeStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop {time}'**
  String tradeStopRecording(String time);

  /// No description provided for @tradeAudioFile.
  ///
  /// In en, this message translates to:
  /// **'Audio file'**
  String get tradeAudioFile;

  /// No description provided for @tradeUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get tradeUploading;

  /// No description provided for @tradeUploadsOnSave.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {size} · uploads on save'**
  String tradeUploadsOnSave(String duration, String size);

  /// No description provided for @tradeVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get tradeVoiceNote;

  /// No description provided for @tradeScreenshots.
  ///
  /// In en, this message translates to:
  /// **'SCREENSHOTS'**
  String get tradeScreenshots;

  /// No description provided for @tradeVoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'VOICE NOTES'**
  String get tradeVoiceNotes;

  /// No description provided for @tradeRemoveFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this file?'**
  String get tradeRemoveFileTitle;

  /// No description provided for @tradeRemoveFileBody.
  ///
  /// In en, this message translates to:
  /// **'It is deleted from storage as well as from this entry.'**
  String get tradeRemoveFileBody;

  /// No description provided for @tradeRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get tradeRemove;

  /// No description provided for @tradeTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tradeTags;

  /// No description provided for @tradeNoTags.
  ///
  /// In en, this message translates to:
  /// **'No tags yet — they drive the edge report.'**
  String get tradeNoTags;

  /// No description provided for @tradeAddTagHint.
  ///
  /// In en, this message translates to:
  /// **'Add a tag and press enter'**
  String get tradeAddTagHint;

  /// No description provided for @tradeLiveTicket.
  ///
  /// In en, this message translates to:
  /// **'Live ticket'**
  String get tradeLiveTicket;

  /// No description provided for @tradeEstimatedPnl.
  ///
  /// In en, this message translates to:
  /// **'ESTIMATED P&L'**
  String get tradeEstimatedPnl;

  /// No description provided for @tradePips.
  ///
  /// In en, this message translates to:
  /// **'{pips} pips'**
  String tradePips(String pips);

  /// No description provided for @tradeRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get tradeRequired;

  /// No description provided for @tradeNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get tradeNumber;

  /// No description provided for @tradeMustBePositive.
  ///
  /// In en, this message translates to:
  /// **'Must be > 0'**
  String get tradeMustBePositive;

  /// No description provided for @tradeLevelsHint.
  ///
  /// In en, this message translates to:
  /// **'Add a stop loss or a take profit, or the exit is marked at the latest price.'**
  String get tradeLevelsHint;

  /// No description provided for @tradeLevelBuyStop.
  ///
  /// In en, this message translates to:
  /// **'For a BUY the stop loss must be below the entry.'**
  String get tradeLevelBuyStop;

  /// No description provided for @tradeLevelBuyTake.
  ///
  /// In en, this message translates to:
  /// **'For a BUY the take profit must be above the entry.'**
  String get tradeLevelBuyTake;

  /// No description provided for @tradeLevelSellStop.
  ///
  /// In en, this message translates to:
  /// **'For a SELL the stop loss must be above the entry.'**
  String get tradeLevelSellStop;

  /// No description provided for @tradeLevelSellTake.
  ///
  /// In en, this message translates to:
  /// **'For a SELL the take profit must be below the entry.'**
  String get tradeLevelSellTake;

  /// No description provided for @riskLabel.
  ///
  /// In en, this message translates to:
  /// **'RISK'**
  String get riskLabel;

  /// No description provided for @riskRewardLabel.
  ///
  /// In en, this message translates to:
  /// **'REWARD'**
  String get riskRewardLabel;

  /// No description provided for @riskHintEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add an entry, a level and a size to preview the risk.'**
  String get riskHintEmpty;

  /// No description provided for @riskStopWrongBuy.
  ///
  /// In en, this message translates to:
  /// **'A buy\'s stop sits below the entry — this one is above it.'**
  String get riskStopWrongBuy;

  /// No description provided for @riskStopWrongSell.
  ///
  /// In en, this message translates to:
  /// **'A sell\'s stop sits above the entry — this one is below it.'**
  String get riskStopWrongSell;

  /// No description provided for @riskTakeWrongBuy.
  ///
  /// In en, this message translates to:
  /// **'A buy\'s target sits above the entry — this one is below it.'**
  String get riskTakeWrongBuy;

  /// No description provided for @riskTakeWrongSell.
  ///
  /// In en, this message translates to:
  /// **'A sell\'s target sits below the entry — this one is above it.'**
  String get riskTakeWrongSell;

  /// No description provided for @tradeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load this trade: {message}'**
  String tradeLoadFailed(String message);

  /// No description provided for @tradeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {message}'**
  String tradeSaveFailed(String message);

  /// No description provided for @tradeSaveTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The save request timed out. Check your connection and press Save again.'**
  String get tradeSaveTimedOut;

  /// No description provided for @tradeMediaSavedNote.
  ///
  /// In en, this message translates to:
  /// **'The trade itself was saved — press Save again to retry the media.'**
  String get tradeMediaSavedNote;

  /// No description provided for @tradeExitBeforeEntryError.
  ///
  /// In en, this message translates to:
  /// **'The exit time cannot be before the entry time.'**
  String get tradeExitBeforeEntryError;

  /// No description provided for @tradeSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Sign in again.'**
  String get tradeSessionExpired;

  /// No description provided for @tradeEnterEntryAndSize.
  ///
  /// In en, this message translates to:
  /// **'Enter the entry price and the size before saving.'**
  String get tradeEnterEntryAndSize;

  /// No description provided for @tradeSetOpenedTime.
  ///
  /// In en, this message translates to:
  /// **'Set the opened time — the candles after it decide the exit price and time.'**
  String get tradeSetOpenedTime;

  /// No description provided for @tradePickSymbolFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick the symbol from the list — the exit is read from its candles.'**
  String get tradePickSymbolFirst;

  /// No description provided for @tradeOpenedInFuture.
  ///
  /// In en, this message translates to:
  /// **'The opened time is in the future. Pick a past time.'**
  String get tradeOpenedInFuture;

  /// No description provided for @tradeEnterEntryFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter the entry price first.'**
  String get tradeEnterEntryFirst;

  /// No description provided for @tradePickSymbolToFindExit.
  ///
  /// In en, this message translates to:
  /// **'Pick a symbol from the list first, then find the exit.'**
  String get tradePickSymbolToFindExit;

  /// No description provided for @tradeNoCandles.
  ///
  /// In en, this message translates to:
  /// **'No candles were returned for that time. Check the symbol and the opened time, then try again.'**
  String get tradeNoCandles;

  /// No description provided for @tradeCandlesUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The candles could not be read. Check your connection and try again.'**
  String get tradeCandlesUnreadable;

  /// No description provided for @tradeRemovePendingFailed.
  ///
  /// In en, this message translates to:
  /// **'The file was removed here but could not be deleted from storage: {message}'**
  String tradeRemovePendingFailed(String message);

  /// No description provided for @tradeRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove that file: {message}'**
  String tradeRemoveFailed(String message);

  /// No description provided for @tradeRecordingOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open that recording.'**
  String get tradeRecordingOpenFailed;

  /// No description provided for @tradeRecordingPlayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not play that recording.'**
  String get tradeRecordingPlayFailed;

  /// No description provided for @journalRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh: {message}'**
  String journalRefreshFailed(String message);

  /// No description provided for @journalRescueBanner.
  ///
  /// In en, this message translates to:
  /// **'Your {count, plural, =1{1 trade is} other{{count} trades are}} saved, but the list came back empty — most often a dropped session. Pull down to try again.'**
  String journalRescueBanner(int count);

  /// No description provided for @journalRowLine.
  ///
  /// In en, this message translates to:
  /// **'{date} · {entry} → {exit} · {lots} lots'**
  String journalRowLine(String date, String entry, String exit, String lots);

  /// No description provided for @journalResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get journalResult;
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
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
