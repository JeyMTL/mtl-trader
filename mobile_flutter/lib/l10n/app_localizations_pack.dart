// GENERATED FILE — do not edit by hand.
// Regenerate with `node scripts/make-locales.mjs` from lib/l10n/app_en.arb.
import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';
import 'gen/app_localizations_en.dart';

/// Strings served from a downloaded language pack.
///
/// A pack is a key → template map. A key it leaves out falls back to the
/// bundled English message, so a partial translation is always safe to ship.
class AppLocalizationsPack extends AppLocalizations {
  AppLocalizationsPack(Locale locale, Map<String, String> messages)
      : _messages = messages,
        super(locale.languageCode);

  final Map<String, String> _messages;

  static final AppLocalizations _en = AppLocalizationsEn();

  String? _read(String key) => _messages[key];

  /// Substitutes `{name}` with a value the screen already formatted, so
  /// money, percentages and dates keep the shape the caller chose.
  static String _fill(String template, Map<String, Object?> values) {
    var text = template;
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return text;
  }

  @override
  String get appTitle => _read('appTitle') ?? _en.appTitle;

  @override
  String get retry => _read('retry') ?? _en.retry;

  @override
  String get cancel => _read('cancel') ?? _en.cancel;

  @override
  String get refresh => _read('refresh') ?? _en.refresh;

  @override
  String get language => _read('language') ?? _en.language;

  @override
  String get languageSystem => _read('languageSystem') ?? _en.languageSystem;

  @override
  String get languageSystemSubtitle => _read('languageSystemSubtitle') ?? _en.languageSystemSubtitle;

  @override
  String get searchLanguages => _read('searchLanguages') ?? _en.searchLanguages;

  @override
  String get noLanguageMatches => _read('noLanguageMatches') ?? _en.noLanguageMatches;

  @override
  String get languageBuiltIn => _read('languageBuiltIn') ?? _en.languageBuiltIn;

  @override
  String get languageDownload => _read('languageDownload') ?? _en.languageDownload;

  @override
  String get languageDownloading => _read('languageDownloading') ?? _en.languageDownloading;

  @override
  String get languageDownloaded => _read('languageDownloaded') ?? _en.languageDownloaded;

  @override
  String get languageRemove => _read('languageRemove') ?? _en.languageRemove;

  @override
  String get languageEnglishFallback => _read('languageEnglishFallback') ?? _en.languageEnglishFallback;

  @override
  String get languagePackFailed => _read('languagePackFailed') ?? _en.languagePackFailed;

  @override
  String get navDesk => _read('navDesk') ?? _en.navDesk;

  @override
  String get navJournal => _read('navJournal') ?? _en.navJournal;

  @override
  String get navAnalytics => _read('navAnalytics') ?? _en.navAnalytics;

  @override
  String get navCalendar => _read('navCalendar') ?? _en.navCalendar;

  @override
  String get navAccount => _read('navAccount') ?? _en.navAccount;

  @override
  String get newTrade => _read('newTrade') ?? _en.newTrade;

  @override
  String get timeEdge => _read('timeEdge') ?? _en.timeEdge;

  @override
  String get brandName => _read('brandName') ?? _en.brandName;

  @override
  String get brandOpenPlans => _read('brandOpenPlans') ?? _en.brandOpenPlans;

  @override
  String get upgrade => _read('upgrade') ?? _en.upgrade;

  @override
  String get rules => _read('rules') ?? _en.rules;

  @override
  String get loginHeadline => _read('loginHeadline') ?? _en.loginHeadline;

  @override
  String get loginTagline => _read('loginTagline') ?? _en.loginTagline;

  @override
  String get continueWithGoogle => _read('continueWithGoogle') ?? _en.continueWithGoogle;

  @override
  String get signIn => _read('signIn') ?? _en.signIn;

  @override
  String get createAccount => _read('createAccount') ?? _en.createAccount;

  @override
  String get emailLabel => _read('emailLabel') ?? _en.emailLabel;

  @override
  String get emailHint => _read('emailHint') ?? _en.emailHint;

  @override
  String get passwordLabel => _read('passwordLabel') ?? _en.passwordLabel;

  @override
  String get showPassword => _read('showPassword') ?? _en.showPassword;

  @override
  String get hidePassword => _read('hidePassword') ?? _en.hidePassword;

  @override
  String get emailInvalid => _read('emailInvalid') ?? _en.emailInvalid;

  @override
  String get passwordTooShort => _read('passwordTooShort') ?? _en.passwordTooShort;

  @override
  String get loginFootnote => _read('loginFootnote') ?? _en.loginFootnote;

  @override
  String get googleOpenFailed => _read('googleOpenFailed') ?? _en.googleOpenFailed;

  @override
  String get googleTimedOut => _read('googleTimedOut') ?? _en.googleTimedOut;

  @override
  String get googleStartFailed => _read('googleStartFailed') ?? _en.googleStartFailed;

  @override
  String get signInUnreachable => _read('signInUnreachable') ?? _en.signInUnreachable;

  @override
  String get googleFinishNotice => _read('googleFinishNotice') ?? _en.googleFinishNotice;

  @override
  String confirmEmailNotice(String email) {
    final template = _read('confirmEmailNotice');
    if (template == null) return _en.confirmEmailNotice(email);
    return _fill(template, <String, Object?>{'email': email});
  }

  @override
  String get accountBalance => _read('accountBalance') ?? _en.accountBalance;

  @override
  String get inProfit => _read('inProfit') ?? _en.inProfit;

  @override
  String get inDrawdown => _read('inDrawdown') ?? _en.inDrawdown;

  @override
  String get deposits => _read('deposits') ?? _en.deposits;

  @override
  String get bestTrade => _read('bestTrade') ?? _en.bestTrade;

  @override
  String get worstTrade => _read('worstTrade') ?? _en.worstTrade;

  @override
  String netSummary(String pnl, int closed, int wins, int losses) {
    final template = _read('netSummary');
    if (template == null) return _en.netSummary(pnl, closed, wins, losses);
    return _fill(template, <String, Object?>{'pnl': pnl, 'closed': closed, 'wins': wins, 'losses': losses});
  }

  @override
  String get importHistoryHint => _read('importHistoryHint') ?? _en.importHistoryHint;

  @override
  String get winRate => _read('winRate') ?? _en.winRate;

  @override
  String get profitFactor => _read('profitFactor') ?? _en.profitFactor;

  @override
  String get maxDrawdown => _read('maxDrawdown') ?? _en.maxDrawdown;

  @override
  String get avgPerTrade => _read('avgPerTrade') ?? _en.avgPerTrade;

  @override
  String winnersCount(int count) {
    final template = _read('winnersCount');
    if (template == null) return _en.winnersCount(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get peakToTrough => _read('peakToTrough') ?? _en.peakToTrough;

  @override
  String get expectancy => _read('expectancy') ?? _en.expectancy;

  @override
  String get thisMonth => _read('thisMonth') ?? _en.thisMonth;

  @override
  String monthTrades(int count) {
    final template = _read('monthTrades');
    if (template == null) return _en.monthTrades(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String greenDays(int count) {
    final template = _read('greenDays');
    if (template == null) return _en.greenDays(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get monthWinRate => _read('monthWinRate') ?? _en.monthWinRate;

  @override
  String timeEdgeSubtitle(String timezone, String hold) {
    final template = _read('timeEdgeSubtitle');
    if (template == null) return _en.timeEdgeSubtitle(timezone, hold);
    return _fill(template, <String, Object?>{'timezone': timezone, 'hold': hold});
  }

  @override
  String get report => _read('report') ?? _en.report;

  @override
  String get noTimedTradesTitle => _read('noTimedTradesTitle') ?? _en.noTimedTradesTitle;

  @override
  String get noTimedTradesBody => _read('noTimedTradesBody') ?? _en.noTimedTradesBody;

  @override
  String get mostProfitableHour => _read('mostProfitableHour') ?? _en.mostProfitableHour;

  @override
  String get mostLosses => _read('mostLosses') ?? _en.mostLosses;

  @override
  String get bestSession => _read('bestSession') ?? _en.bestSession;

  @override
  String get weakestSession => _read('weakestSession') ?? _en.weakestSession;

  @override
  String get needsMoreTrades => _read('needsMoreTrades') ?? _en.needsMoreTrades;

  @override
  String periodStats(int trades, String winRate) {
    final template = _read('periodStats');
    if (template == null) return _en.periodStats(trades, winRate);
    return _fill(template, <String, Object?>{'trades': trades, 'winRate': winRate});
  }

  @override
  String get thinSampleNote => _read('thinSampleNote') ?? _en.thinSampleNote;

  @override
  String get journalSectionTitle => _read('journalSectionTitle') ?? _en.journalSectionTitle;

  @override
  String get journalSectionSubtitle => _read('journalSectionSubtitle') ?? _en.journalSectionSubtitle;

  @override
  String get nothingJournaledTitle => _read('nothingJournaledTitle') ?? _en.nothingJournaledTitle;

  @override
  String get nothingJournaledBody => _read('nothingJournaledBody') ?? _en.nothingJournaledBody;

  @override
  String get recentFills => _read('recentFills') ?? _en.recentFills;

  @override
  String get noFillsTitle => _read('noFillsTitle') ?? _en.noFillsTitle;

  @override
  String get startHere => _read('startHere') ?? _en.startHere;

  @override
  String get startHeadline => _read('startHeadline') ?? _en.startHeadline;

  @override
  String get startStep1 => _read('startStep1') ?? _en.startStep1;

  @override
  String get startStep2 => _read('startStep2') ?? _en.startStep2;

  @override
  String get startStep3 => _read('startStep3') ?? _en.startStep3;

  @override
  String get seeTimeReport => _read('seeTimeReport') ?? _en.seeTimeReport;

  @override
  String get couldNotLoadDesk => _read('couldNotLoadDesk') ?? _en.couldNotLoadDesk;

  @override
  String a11yProfit(String amount) {
    final template = _read('a11yProfit');
    if (template == null) return _en.a11yProfit(amount);
    return _fill(template, <String, Object?>{'amount': amount});
  }

  @override
  String a11yLoss(String amount) {
    final template = _read('a11yLoss');
    if (template == null) return _en.a11yLoss(amount);
    return _fill(template, <String, Object?>{'amount': amount});
  }

  @override
  String a11yBreakEven(String amount) {
    final template = _read('a11yBreakEven');
    if (template == null) return _en.a11yBreakEven(amount);
    return _fill(template, <String, Object?>{'amount': amount});
  }

  @override
  String a11yEquityCurve(String change) {
    final template = _read('a11yEquityCurve');
    if (template == null) return _en.a11yEquityCurve(change);
    return _fill(template, <String, Object?>{'change': change});
  }

  @override
  String get a11yHourChart => _read('a11yHourChart') ?? _en.a11yHourChart;

  @override
  String a11yScreenshots(int count) {
    final template = _read('a11yScreenshots');
    if (template == null) return _en.a11yScreenshots(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String a11yVoiceNotes(int count) {
    final template = _read('a11yVoiceNotes');
    if (template == null) return _en.a11yVoiceNotes(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get languageSubtitle => _read('languageSubtitle') ?? _en.languageSubtitle;

  @override
  String get journalTitle => _read('journalTitle') ?? _en.journalTitle;

  @override
  String get journalSearchHint => _read('journalSearchHint') ?? _en.journalSearchHint;

  @override
  String get journalSessionAll => _read('journalSessionAll') ?? _en.journalSessionAll;

  @override
  String get journalSessionAsian => _read('journalSessionAsian') ?? _en.journalSessionAsian;

  @override
  String get journalSessionLondon => _read('journalSessionLondon') ?? _en.journalSessionLondon;

  @override
  String get journalSessionNewYork => _read('journalSessionNewYork') ?? _en.journalSessionNewYork;

  @override
  String get journalSessionSydney => _read('journalSessionSydney') ?? _en.journalSessionSydney;

  @override
  String get journalFilterAll => _read('journalFilterAll') ?? _en.journalFilterAll;

  @override
  String get journalFilterWins => _read('journalFilterWins') ?? _en.journalFilterWins;

  @override
  String get journalFilterLosses => _read('journalFilterLosses') ?? _en.journalFilterLosses;

  @override
  String get journalLoading => _read('journalLoading') ?? _en.journalLoading;

  @override
  String journalCountSummary(int count, String pnl) {
    final template = _read('journalCountSummary');
    if (template == null) return _en.journalCountSummary(count, pnl);
    return _fill(template, <String, Object?>{'count': count, 'pnl': pnl});
  }

  @override
  String get journalLoadMore => _read('journalLoadMore') ?? _en.journalLoadMore;

  @override
  String get journalClearMenu => _read('journalClearMenu') ?? _en.journalClearMenu;

  @override
  String get journalEmptyTitle => _read('journalEmptyTitle') ?? _en.journalEmptyTitle;

  @override
  String get journalEmptyBody => _read('journalEmptyBody') ?? _en.journalEmptyBody;

  @override
  String get journalErrorTitle => _read('journalErrorTitle') ?? _en.journalErrorTitle;

  @override
  String get deleteTradeTitle => _read('deleteTradeTitle') ?? _en.deleteTradeTitle;

  @override
  String deleteTradeBody(String symbol) {
    final template = _read('deleteTradeBody');
    if (template == null) return _en.deleteTradeBody(symbol);
    return _fill(template, <String, Object?>{'symbol': symbol});
  }

  @override
  String get deleteAction => _read('deleteAction') ?? _en.deleteAction;

  @override
  String get deleteDone => _read('deleteDone') ?? _en.deleteDone;

  @override
  String deleteFailed(String error) {
    final template = _read('deleteFailed');
    if (template == null) return _en.deleteFailed(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String get clearJournalTitle => _read('clearJournalTitle') ?? _en.clearJournalTitle;

  @override
  String get clearJournalBody => _read('clearJournalBody') ?? _en.clearJournalBody;

  @override
  String get clearAllAction => _read('clearAllAction') ?? _en.clearAllAction;

  @override
  String clearFailed(String error) {
    final template = _read('clearFailed');
    if (template == null) return _en.clearFailed(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String get analyticsEmptyTitle => _read('analyticsEmptyTitle') ?? _en.analyticsEmptyTitle;

  @override
  String get analyticsEmptyBody => _read('analyticsEmptyBody') ?? _en.analyticsEmptyBody;

  @override
  String get analyticsErrorTitle => _read('analyticsErrorTitle') ?? _en.analyticsErrorTitle;

  @override
  String get analyticsErrorBody => _read('analyticsErrorBody') ?? _en.analyticsErrorBody;

  @override
  String get timeEdgeDescription => _read('timeEdgeDescription') ?? _en.timeEdgeDescription;

  @override
  String get performanceSummaryTitle => _read('performanceSummaryTitle') ?? _en.performanceSummaryTitle;

  @override
  String get performanceSummarySubtitle => _read('performanceSummarySubtitle') ?? _en.performanceSummarySubtitle;

  @override
  String get summaryTrades => _read('summaryTrades') ?? _en.summaryTrades;

  @override
  String summaryTradesFoot(int count) {
    final template = _read('summaryTradesFoot');
    if (template == null) return _en.summaryTradesFoot(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String summaryWinLoss(int wins, int losses) {
    final template = _read('summaryWinLoss');
    if (template == null) return _en.summaryWinLoss(wins, losses);
    return _fill(template, <String, Object?>{'wins': wins, 'losses': losses});
  }

  @override
  String summaryGrossFoot(String profit, String loss) {
    final template = _read('summaryGrossFoot');
    if (template == null) return _en.summaryGrossFoot(profit, loss);
    return _fill(template, <String, Object?>{'profit': profit, 'loss': loss});
  }

  @override
  String get summaryAverageTrade => _read('summaryAverageTrade') ?? _en.summaryAverageTrade;

  @override
  String summaryNetFoot(String net) {
    final template = _read('summaryNetFoot');
    if (template == null) return _en.summaryNetFoot(net);
    return _fill(template, <String, Object?>{'net': net});
  }

  @override
  String summaryBestTradeFoot(String worst) {
    final template = _read('summaryBestTradeFoot');
    if (template == null) return _en.summaryBestTradeFoot(worst);
    return _fill(template, <String, Object?>{'worst': worst});
  }

  @override
  String summaryMonthFoot(int count) {
    final template = _read('summaryMonthFoot');
    if (template == null) return _en.summaryMonthFoot(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get monthlyPnlTitle => _read('monthlyPnlTitle') ?? _en.monthlyPnlTitle;

  @override
  String get monthlyPnlSubtitle => _read('monthlyPnlSubtitle') ?? _en.monthlyPnlSubtitle;

  @override
  String get pnlByDayTitle => _read('pnlByDayTitle') ?? _en.pnlByDayTitle;

  @override
  String get pnlByDayRecent => _read('pnlByDayRecent') ?? _en.pnlByDayRecent;

  @override
  String pnlByDayBestWorst(String bestDay, String bestPnl, String worstDay, String worstPnl) {
    final template = _read('pnlByDayBestWorst');
    if (template == null) return _en.pnlByDayBestWorst(bestDay, bestPnl, worstDay, worstPnl);
    return _fill(template, <String, Object?>{'bestDay': bestDay, 'bestPnl': bestPnl, 'worstDay': worstDay, 'worstPnl': worstPnl});
  }

  @override
  String get legendLoss => _read('legendLoss') ?? _en.legendLoss;

  @override
  String get legendNoTrades => _read('legendNoTrades') ?? _en.legendNoTrades;

  @override
  String get legendProfit => _read('legendProfit') ?? _en.legendProfit;

  @override
  String get tapADay => _read('tapADay') ?? _en.tapADay;

  @override
  String get performanceBySymbol => _read('performanceBySymbol') ?? _en.performanceBySymbol;

  @override
  String get performanceBySymbolSubtitle => _read('performanceBySymbolSubtitle') ?? _en.performanceBySymbolSubtitle;

  @override
  String get performanceByTag => _read('performanceByTag') ?? _en.performanceByTag;

  @override
  String get performanceByTagSubtitle => _read('performanceByTagSubtitle') ?? _en.performanceByTagSubtitle;

  @override
  String symbolStats(int trades, String winRate) {
    final template = _read('symbolStats');
    if (template == null) return _en.symbolStats(trades, winRate);
    return _fill(template, <String, Object?>{'trades': trades, 'winRate': winRate});
  }

  @override
  String tagStats(int trades, int wins, int losses, String winRate) {
    final template = _read('tagStats');
    if (template == null) return _en.tagStats(trades, wins, losses, winRate);
    return _fill(template, <String, Object?>{'trades': trades, 'wins': wins, 'losses': losses, 'winRate': winRate});
  }

  @override
  String get a11yRunningCurve => _read('a11yRunningCurve') ?? _en.a11yRunningCurve;

  @override
  String a11yHeatmapDay(String day, String pnl, int trades) {
    final template = _read('a11yHeatmapDay');
    if (template == null) return _en.a11yHeatmapDay(day, pnl, trades);
    return _fill(template, <String, Object?>{'day': day, 'pnl': pnl, 'trades': trades});
  }

  @override
  String a11yHeatmapEmpty(String day) {
    final template = _read('a11yHeatmapEmpty');
    if (template == null) return _en.a11yHeatmapEmpty(day);
    return _fill(template, <String, Object?>{'day': day});
  }

  @override
  String get account => _read('account') ?? _en.account;

  @override
  String get accountSignOutQuestion => _read('accountSignOutQuestion') ?? _en.accountSignOutQuestion;

  @override
  String get accountSignOutBody => _read('accountSignOutBody') ?? _en.accountSignOutBody;

  @override
  String get signOut => _read('signOut') ?? _en.signOut;

  @override
  String get accountPlan => _read('accountPlan') ?? _en.accountPlan;

  @override
  String get accountStatus => _read('accountStatus') ?? _en.accountStatus;

  @override
  String get accountTradeLimit => _read('accountTradeLimit') ?? _en.accountTradeLimit;

  @override
  String get accountUnlimited => _read('accountUnlimited') ?? _en.accountUnlimited;

  @override
  String get accountTimezone => _read('accountTimezone') ?? _en.accountTimezone;

  @override
  String get accountChange => _read('accountChange') ?? _en.accountChange;

  @override
  String get accountTrialEnds => _read('accountTrialEnds') ?? _en.accountTrialEnds;

  @override
  String get accountAccessUntil => _read('accountAccessUntil') ?? _en.accountAccessUntil;

  @override
  String get accountPaidThrough => _read('accountPaidThrough') ?? _en.accountPaidThrough;

  @override
  String get accountViewPlans => _read('accountViewPlans') ?? _en.accountViewPlans;

  @override
  String get accountBuyPlan => _read('accountBuyPlan') ?? _en.accountBuyPlan;

  @override
  String get accountSubscription => _read('accountSubscription') ?? _en.accountSubscription;

  @override
  String get accountSignedIn => _read('accountSignedIn') ?? _en.accountSignedIn;

  @override
  String get accountSubError => _read('accountSubError') ?? _en.accountSubError;

  @override
  String get commonTryAgain => _read('commonTryAgain') ?? _en.commonTryAgain;

  @override
  String get commonSave => _read('commonSave') ?? _en.commonSave;

  @override
  String get sectionTrading => _read('sectionTrading') ?? _en.sectionTrading;

  @override
  String get sectionPreferences => _read('sectionPreferences') ?? _en.sectionPreferences;

  @override
  String get sectionSupport => _read('sectionSupport') ?? _en.sectionSupport;

  @override
  String get sectionAbout => _read('sectionAbout') ?? _en.sectionAbout;

  @override
  String get accountAppearance => _read('accountAppearance') ?? _en.accountAppearance;

  @override
  String get accountAppearanceBody => _read('accountAppearanceBody') ?? _en.accountAppearanceBody;

  @override
  String get themeDark => _read('themeDark') ?? _en.themeDark;

  @override
  String get themeLight => _read('themeLight') ?? _en.themeLight;

  @override
  String get themeBlue => _read('themeBlue') ?? _en.themeBlue;

  @override
  String get themeSystem => _read('themeSystem') ?? _en.themeSystem;

  @override
  String get accountHelp => _read('accountHelp') ?? _en.accountHelp;

  @override
  String get accountHelpBody => _read('accountHelpBody') ?? _en.accountHelpBody;

  @override
  String get accountEmailSupport => _read('accountEmailSupport') ?? _en.accountEmailSupport;

  @override
  String get accountRate => _read('accountRate') ?? _en.accountRate;

  @override
  String get accountAbout => _read('accountAbout') ?? _en.accountAbout;

  @override
  String get accountAboutBody => _read('accountAboutBody') ?? _en.accountAboutBody;

  @override
  String get accountPrivateMedia => _read('accountPrivateMedia') ?? _en.accountPrivateMedia;

  @override
  String get accountPrivateMediaBody => _read('accountPrivateMediaBody') ?? _en.accountPrivateMediaBody;

  @override
  String get accountFooter => _read('accountFooter') ?? _en.accountFooter;

  @override
  String get accountRules => _read('accountRules') ?? _en.accountRules;

  @override
  String get accountConnectMt5 => _read('accountConnectMt5') ?? _en.accountConnectMt5;

  @override
  String get accountImport => _read('accountImport') ?? _en.accountImport;

  @override
  String get accountBacktest => _read('accountBacktest') ?? _en.accountBacktest;

  @override
  String get accountPropFirm => _read('accountPropFirm') ?? _en.accountPropFirm;

  @override
  String get accountTimezoneRow => _read('accountTimezoneRow') ?? _en.accountTimezoneRow;

  @override
  String get accountTimezoneDialog => _read('accountTimezoneDialog') ?? _en.accountTimezoneDialog;

  @override
  String accountTimezoneSaved(String zone) {
    final template = _read('accountTimezoneSaved');
    if (template == null) return _en.accountTimezoneSaved(zone);
    return _fill(template, <String, Object?>{'zone': zone});
  }

  @override
  String accountTimezoneFailed(String error) {
    final template = _read('accountTimezoneFailed');
    if (template == null) return _en.accountTimezoneFailed(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String get accountPicture => _read('accountPicture') ?? _en.accountPicture;

  @override
  String get accountPictureBody => _read('accountPictureBody') ?? _en.accountPictureBody;

  @override
  String get accountPictureCleared => _read('accountPictureCleared') ?? _en.accountPictureCleared;

  @override
  String get accountPictureUpdated => _read('accountPictureUpdated') ?? _en.accountPictureUpdated;

  @override
  String accountPictureFailed(String error) {
    final template = _read('accountPictureFailed');
    if (template == null) return _en.accountPictureFailed(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String get accountStoreFailed => _read('accountStoreFailed') ?? _en.accountStoreFailed;

  @override
  String get accountMailFailed => _read('accountMailFailed') ?? _en.accountMailFailed;

  @override
  String get accountDailyStop => _read('accountDailyStop') ?? _en.accountDailyStop;

  @override
  String get accountDailyStopBody => _read('accountDailyStopBody') ?? _en.accountDailyStopBody;

  @override
  String get accountLossBudget => _read('accountLossBudget') ?? _en.accountLossBudget;

  @override
  String get accountMaxEntries => _read('accountMaxEntries') ?? _en.accountMaxEntries;

  @override
  String get accountWhenReached => _read('accountWhenReached') ?? _en.accountWhenReached;

  @override
  String get accountOff => _read('accountOff') ?? _en.accountOff;

  @override
  String get accountNoCap => _read('accountNoCap') ?? _en.accountNoCap;

  @override
  String get accountLoadingRules => _read('accountLoadingRules') ?? _en.accountLoadingRules;

  @override
  String get accountEditRules => _read('accountEditRules') ?? _en.accountEditRules;

  @override
  String get lockSoft => _read('lockSoft') ?? _en.lockSoft;

  @override
  String get lockHard => _read('lockHard') ?? _en.lockHard;

  @override
  String get lockJournalOnly => _read('lockJournalOnly') ?? _en.lockJournalOnly;

  @override
  String get accountStopNone => _read('accountStopNone') ?? _en.accountStopNone;

  @override
  String get accountStopSoft => _read('accountStopSoft') ?? _en.accountStopSoft;

  @override
  String get accountStopHard => _read('accountStopHard') ?? _en.accountStopHard;

  @override
  String get accountStopOff => _read('accountStopOff') ?? _en.accountStopOff;

  @override
  String get rulesIntro => _read('rulesIntro') ?? _en.rulesIntro;

  @override
  String get rulesYourRules => _read('rulesYourRules') ?? _en.rulesYourRules;

  @override
  String get rulesYourRulesBody => _read('rulesYourRulesBody') ?? _en.rulesYourRulesBody;

  @override
  String get rulesEmpty => _read('rulesEmpty') ?? _en.rulesEmpty;

  @override
  String get rulesAdd => _read('rulesAdd') ?? _en.rulesAdd;

  @override
  String get rulesRemove => _read('rulesRemove') ?? _en.rulesRemove;

  @override
  String get rulesDays => _read('rulesDays') ?? _en.rulesDays;

  @override
  String get rulesDaysBody => _read('rulesDaysBody') ?? _en.rulesDaysBody;

  @override
  String get rulesDailyStop => _read('rulesDailyStop') ?? _en.rulesDailyStop;

  @override
  String get rulesDailyStopBody => _read('rulesDailyStopBody') ?? _en.rulesDailyStopBody;

  @override
  String get rulesLossBudget => _read('rulesLossBudget') ?? _en.rulesLossBudget;

  @override
  String get rulesMaxEntries => _read('rulesMaxEntries') ?? _en.rulesMaxEntries;

  @override
  String get rulesWhenReached => _read('rulesWhenReached') ?? _en.rulesWhenReached;

  @override
  String get rulesJournalOnlyBlurb => _read('rulesJournalOnlyBlurb') ?? _en.rulesJournalOnlyBlurb;

  @override
  String get rulesSoftBlurb => _read('rulesSoftBlurb') ?? _en.rulesSoftBlurb;

  @override
  String get rulesHardBlurb => _read('rulesHardBlurb') ?? _en.rulesHardBlurb;

  @override
  String get rulesSessions => _read('rulesSessions') ?? _en.rulesSessions;

  @override
  String get rulesSessionsBody => _read('rulesSessionsBody') ?? _en.rulesSessionsBody;

  @override
  String get rulesNoSessions => _read('rulesNoSessions') ?? _en.rulesNoSessions;

  @override
  String get rulesSessionName => _read('rulesSessionName') ?? _en.rulesSessionName;

  @override
  String get rulesRemoveSession => _read('rulesRemoveSession') ?? _en.rulesRemoveSession;

  @override
  String get rulesAddSession => _read('rulesAddSession') ?? _en.rulesAddSession;

  @override
  String get rulesNewSession => _read('rulesNewSession') ?? _en.rulesNewSession;

  @override
  String get rulesSessionFallback => _read('rulesSessionFallback') ?? _en.rulesSessionFallback;

  @override
  String get rulesReminders => _read('rulesReminders') ?? _en.rulesReminders;

  @override
  String get rulesRemindersBody => _read('rulesRemindersBody') ?? _en.rulesRemindersBody;

  @override
  String get rulesRemindersOn => _read('rulesRemindersOn') ?? _en.rulesRemindersOn;

  @override
  String get rulesRemindersOff => _read('rulesRemindersOff') ?? _en.rulesRemindersOff;

  @override
  String get rulesReminderLead => _read('rulesReminderLead') ?? _en.rulesReminderLead;

  @override
  String rulesReminderMinutes(String minutes) {
    final template = _read('rulesReminderMinutes');
    if (template == null) return _en.rulesReminderMinutes(minutes);
    return _fill(template, <String, Object?>{'minutes': minutes});
  }

  @override
  String get rulesNotes => _read('rulesNotes') ?? _en.rulesNotes;

  @override
  String get rulesNotesHint => _read('rulesNotesHint') ?? _en.rulesNotesHint;

  @override
  String get rulesSave => _read('rulesSave') ?? _en.rulesSave;

  @override
  String get rulesSaving => _read('rulesSaving') ?? _en.rulesSaving;

  @override
  String get rulesSaved => _read('rulesSaved') ?? _en.rulesSaved;

  @override
  String rulesSaveError(String error) {
    final template = _read('rulesSaveError');
    if (template == null) return _en.rulesSaveError(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String rulesLoadError(String error) {
    final template = _read('rulesLoadError');
    if (template == null) return _en.rulesLoadError(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String get rulesMaxReached => _read('rulesMaxReached') ?? _en.rulesMaxReached;

  @override
  String get rulesSessionsMax => _read('rulesSessionsMax') ?? _en.rulesSessionsMax;

  @override
  String get lockHardBadge => _read('lockHardBadge') ?? _en.lockHardBadge;

  @override
  String get lockSoftBadge => _read('lockSoftBadge') ?? _en.lockSoftBadge;

  @override
  String get lockDayOver => _read('lockDayOver') ?? _en.lockDayOver;

  @override
  String lockLossBody(String used, String limit) {
    final template = _read('lockLossBody');
    if (template == null) return _en.lockLossBody(used, limit);
    return _fill(template, <String, Object?>{'used': used, 'limit': limit});
  }

  @override
  String lockCapBody(String trades, String max) {
    final template = _read('lockCapBody');
    if (template == null) return _en.lockCapBody(trades, max);
    return _fill(template, <String, Object?>{'trades': trades, 'max': max});
  }

  @override
  String get lockRealised => _read('lockRealised') ?? _en.lockRealised;

  @override
  String get lockEntries => _read('lockEntries') ?? _en.lockEntries;

  @override
  String get lockAfterStop => _read('lockAfterStop') ?? _en.lockAfterStop;

  @override
  String get lockResetsNext => _read('lockResetsNext') ?? _en.lockResetsNext;

  @override
  String lockResetsAt(String clock, String countdown) {
    final template = _read('lockResetsAt');
    if (template == null) return _en.lockResetsAt(clock, countdown);
    return _fill(template, <String, Object?>{'clock': clock, 'countdown': countdown});
  }

  @override
  String get lockHardBody => _read('lockHardBody') ?? _en.lockHardBody;

  @override
  String get lockHardBody2 => _read('lockHardBody2') ?? _en.lockHardBody2;

  @override
  String get lockUnfreezeToday => _read('lockUnfreezeToday') ?? _en.lockUnfreezeToday;

  @override
  String get lockUnfreezing => _read('lockUnfreezing') ?? _en.lockUnfreezing;

  @override
  String get lockGreenDay => _read('lockGreenDay') ?? _en.lockGreenDay;

  @override
  String get lockStopReached => _read('lockStopReached') ?? _en.lockStopReached;

  @override
  String lockBudgetMessage(String used, String limit) {
    final template = _read('lockBudgetMessage');
    if (template == null) return _en.lockBudgetMessage(used, limit);
    return _fill(template, <String, Object?>{'used': used, 'limit': limit});
  }

  @override
  String get lockSoftReached => _read('lockSoftReached') ?? _en.lockSoftReached;

  @override
  String get lockSoftFrozen => _read('lockSoftFrozen') ?? _en.lockSoftFrozen;

  @override
  String get lockFreezerOff => _read('lockFreezerOff') ?? _en.lockFreezerOff;

  @override
  String get lockUnfreeze => _read('lockUnfreeze') ?? _en.lockUnfreeze;

  @override
  String get lockA11yService => _read('lockA11yService') ?? _en.lockA11yService;

  @override
  String get lockA11yServiceBody => _read('lockA11yServiceBody') ?? _en.lockA11yServiceBody;

  @override
  String get lockOverlay => _read('lockOverlay') ?? _en.lockOverlay;

  @override
  String get lockOverlayBody => _read('lockOverlayBody') ?? _en.lockOverlayBody;

  @override
  String get lockInControl => _read('lockInControl') ?? _en.lockInControl;

  @override
  String get lockInControlBody => _read('lockInControlBody') ?? _en.lockInControlBody;

  @override
  String get lockFreezerTitle => _read('lockFreezerTitle') ?? _en.lockFreezerTitle;

  @override
  String get lockFreezerBody => _read('lockFreezerBody') ?? _en.lockFreezerBody;

  @override
  String get lockNotNow => _read('lockNotNow') ?? _en.lockNotNow;

  @override
  String get lockAgree => _read('lockAgree') ?? _en.lockAgree;

  @override
  String get lockDialogTitle => _read('lockDialogTitle') ?? _en.lockDialogTitle;

  @override
  String get lockDialogBody => _read('lockDialogBody') ?? _en.lockDialogBody;

  @override
  String get lockReasonHint => _read('lockReasonHint') ?? _en.lockReasonHint;

  @override
  String get lockReasonFoot => _read('lockReasonFoot') ?? _en.lockReasonFoot;

  @override
  String lockSoftDetail(String used, String limit) {
    final template = _read('lockSoftDetail');
    if (template == null) return _en.lockSoftDetail(used, limit);
    return _fill(template, <String, Object?>{'used': used, 'limit': limit});
  }

  @override
  String get alertsSection => _read('alertsSection') ?? _en.alertsSection;

  @override
  String get alertsBody => _read('alertsBody') ?? _en.alertsBody;

  @override
  String get alertsDailyStop => _read('alertsDailyStop') ?? _en.alertsDailyStop;

  @override
  String get alertsDailyStopBody => _read('alertsDailyStopBody') ?? _en.alertsDailyStopBody;

  @override
  String get alertsLevels => _read('alertsLevels') ?? _en.alertsLevels;

  @override
  String get alertsLevelsBody => _read('alertsLevelsBody') ?? _en.alertsLevelsBody;

  @override
  String get alertsJournal => _read('alertsJournal') ?? _en.alertsJournal;

  @override
  String get alertsJournalBody => _read('alertsJournalBody') ?? _en.alertsJournalBody;

  @override
  String get alertsReminderAt => _read('alertsReminderAt') ?? _en.alertsReminderAt;

  @override
  String get alertsHistory => _read('alertsHistory') ?? _en.alertsHistory;

  @override
  String get alertsHistoryBody => _read('alertsHistoryBody') ?? _en.alertsHistoryBody;

  @override
  String get alertsTitle => _read('alertsTitle') ?? _en.alertsTitle;

  @override
  String get alertsEmpty => _read('alertsEmpty') ?? _en.alertsEmpty;

  @override
  String get alertsEmptyBody => _read('alertsEmptyBody') ?? _en.alertsEmptyBody;

  @override
  String get alertsWhy => _read('alertsWhy') ?? _en.alertsWhy;

  @override
  String get alertsNotShown => _read('alertsNotShown') ?? _en.alertsNotShown;

  @override
  String get alertsClear => _read('alertsClear') ?? _en.alertsClear;

  @override
  String get alertsSendTest => _read('alertsSendTest') ?? _en.alertsSendTest;

  @override
  String get alertsPermissionMissing => _read('alertsPermissionMissing') ?? _en.alertsPermissionMissing;

  @override
  String planTrialDays(int days) {
    final template = _read('planTrialDays');
    if (template == null) return _en.planTrialDays(days);
    return _fill(template, <String, Object?>{'days': days});
  }
}
