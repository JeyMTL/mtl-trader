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
}
