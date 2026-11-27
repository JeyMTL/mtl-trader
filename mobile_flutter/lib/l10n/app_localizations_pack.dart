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
  /// money, percentages and dates keep the shape the caller chose, and
  /// resolves the one ICU form the app uses — `{count, plural, …}`.
  ///
  /// A pack is generated from the English ARB, so a translated pack can hold
  /// either the English plural shape or a plain template; both render here.
  static String _fill(String template, Map<String, Object?> values) {
    var text = template;
    for (var pass = 0; pass < 5; pass++) {
      final plural = _icuPlural.firstMatch(text);
      if (plural == null) break;
      final name = plural.group(1)!;
      var open = plural.start;
      if (open < 0) break;
      var depth = 0;
      var close = open;
      for (; close < text.length; close++) {
        if (text[close] == '{') depth++;
        if (text[close] == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      if (close >= text.length) break;
      final count = (values[name] as num?)?.toInt() ?? 0;
      final body = text.substring(plural.end, close);
      text = text.replaceRange(plural.start, close + 1, _pluralChoice(body, count));
    }
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return text;
  }

  /// The start of a plural construct: `{count, plural,` in any position.
  static final RegExp _icuPlural =
      RegExp(r'\{\s*(\w+)\s*,\s*plural\s*,', dotAll: true);

  /// The option that applies to [count]: an exact `=N` first, then `one` for
  /// a count of one, then `other`.
  static String _pluralChoice(String body, int count) {
    final options = <String, String>{};
    var i = 0;
    while (i < body.length) {
      final key = _pluralOption.matchAsPrefix(body, i);
      if (key == null) {
        i++;
        continue;
      }
      var open = key.end;
      while (open < body.length && body[open].trim().isEmpty) {
        open++;
      }
      if (open >= body.length || body[open] != '{') {
        i = key.end;
        continue;
      }
      var depth = 0;
      var close = open;
      for (; close < body.length; close++) {
        if (body[close] == '{') depth++;
        if (body[close] == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      if (close >= body.length) break;
      options[key.group(0)!] = body.substring(open + 1, close);
      i = close + 1;
    }
    return options['=$count'] ??
        options[count == 1 ? 'one' : 'other'] ??
        options['other'] ??
        '';
  }

  static final RegExp _pluralOption =
      RegExp(r'(=\d+|zero|one|two|few|many|other)');

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

  @override
  String get tradeNewEntry => _read('tradeNewEntry') ?? _en.tradeNewEntry;

  @override
  String get tradeEditEntry => _read('tradeEditEntry') ?? _en.tradeEditEntry;

  @override
  String get tradeSaveChanges => _read('tradeSaveChanges') ?? _en.tradeSaveChanges;

  @override
  String get tradeSaveEntry => _read('tradeSaveEntry') ?? _en.tradeSaveEntry;

  @override
  String get tradeInstrument => _read('tradeInstrument') ?? _en.tradeInstrument;

  @override
  String get tradeSymbol => _read('tradeSymbol') ?? _en.tradeSymbol;

  @override
  String get tradePickInstrument => _read('tradePickInstrument') ?? _en.tradePickInstrument;

  @override
  String get tradeSymbolRequired => _read('tradeSymbolRequired') ?? _en.tradeSymbolRequired;

  @override
  String get tradeBuy => _read('tradeBuy') ?? _en.tradeBuy;

  @override
  String get tradeSell => _read('tradeSell') ?? _en.tradeSell;

  @override
  String get tradePinLevels => _read('tradePinLevels') ?? _en.tradePinLevels;

  @override
  String get tradeStrategy => _read('tradeStrategy') ?? _en.tradeStrategy;

  @override
  String get tradeSavedStrategies => _read('tradeSavedStrategies') ?? _en.tradeSavedStrategies;

  @override
  String tradeSimilarStrategy(String name) {
    final template = _read('tradeSimilarStrategy');
    if (template == null) return _en.tradeSimilarStrategy(name);
    return _fill(template, <String, Object?>{'name': name});
  }

  @override
  String get tradeExecution => _read('tradeExecution') ?? _en.tradeExecution;

  @override
  String get tradePrices => _read('tradePrices') ?? _en.tradePrices;

  @override
  String get tradeEntryPrice => _read('tradeEntryPrice') ?? _en.tradeEntryPrice;

  @override
  String get tradeStopTarget => _read('tradeStopTarget') ?? _en.tradeStopTarget;

  @override
  String get tradeStopLoss => _read('tradeStopLoss') ?? _en.tradeStopLoss;

  @override
  String get tradeTakeProfit => _read('tradeTakeProfit') ?? _en.tradeTakeProfit;

  @override
  String get tradeExit => _read('tradeExit') ?? _en.tradeExit;

  @override
  String get tradeSizeCosts => _read('tradeSizeCosts') ?? _en.tradeSizeCosts;

  @override
  String get tradeSizeLots => _read('tradeSizeLots') ?? _en.tradeSizeLots;

  @override
  String get tradeCommission => _read('tradeCommission') ?? _en.tradeCommission;

  @override
  String get tradeSwap => _read('tradeSwap') ?? _en.tradeSwap;

  @override
  String get tradeNotSet => _read('tradeNotSet') ?? _en.tradeNotSet;

  @override
  String get tradeFoundWithExit => _read('tradeFoundWithExit') ?? _en.tradeFoundWithExit;

  @override
  String get tradeNotFoundYet => _read('tradeNotFoundYet') ?? _en.tradeNotFoundYet;

  @override
  String get tradeExitReadsCandles => _read('tradeExitReadsCandles') ?? _en.tradeExitReadsCandles;

  @override
  String get tradeFindExit => _read('tradeFindExit') ?? _en.tradeFindExit;

  @override
  String get tradeFindAgain => _read('tradeFindAgain') ?? _en.tradeFindAgain;

  @override
  String get tradeSavedExit => _read('tradeSavedExit') ?? _en.tradeSavedExit;

  @override
  String get tradeExitTakeProfit => _read('tradeExitTakeProfit') ?? _en.tradeExitTakeProfit;

  @override
  String get tradeExitStopLoss => _read('tradeExitStopLoss') ?? _en.tradeExitStopLoss;

  @override
  String get tradeExitLatestPrice => _read('tradeExitLatestPrice') ?? _en.tradeExitLatestPrice;

  @override
  String get tradeTimeWindow => _read('tradeTimeWindow') ?? _en.tradeTimeWindow;

  @override
  String get tradeTimeWindowSub => _read('tradeTimeWindowSub') ?? _en.tradeTimeWindowSub;

  @override
  String get tradeOpened => _read('tradeOpened') ?? _en.tradeOpened;

  @override
  String get tradeClosed => _read('tradeClosed') ?? _en.tradeClosed;

  @override
  String get tradeTimeInMarket => _read('tradeTimeInMarket') ?? _en.tradeTimeInMarket;

  @override
  String get tradeSetBothTimes => _read('tradeSetBothTimes') ?? _en.tradeSetBothTimes;

  @override
  String get tradeExitBeforeEntry => _read('tradeExitBeforeEntry') ?? _en.tradeExitBeforeEntry;

  @override
  String get tradeJournal => _read('tradeJournal') ?? _en.tradeJournal;

  @override
  String get tradeJournalSub => _read('tradeJournalSub') ?? _en.tradeJournalSub;

  @override
  String get tradeJournalHint => _read('tradeJournalHint') ?? _en.tradeJournalHint;

  @override
  String get tradeMedia => _read('tradeMedia') ?? _en.tradeMedia;

  @override
  String get tradeMediaSub => _read('tradeMediaSub') ?? _en.tradeMediaSub;

  @override
  String get tradeGallery => _read('tradeGallery') ?? _en.tradeGallery;

  @override
  String get tradeCamera => _read('tradeCamera') ?? _en.tradeCamera;

  @override
  String get tradeRecord => _read('tradeRecord') ?? _en.tradeRecord;

  @override
  String tradeStopRecording(String time) {
    final template = _read('tradeStopRecording');
    if (template == null) return _en.tradeStopRecording(time);
    return _fill(template, <String, Object?>{'time': time});
  }

  @override
  String get tradeAudioFile => _read('tradeAudioFile') ?? _en.tradeAudioFile;

  @override
  String get tradeUploading => _read('tradeUploading') ?? _en.tradeUploading;

  @override
  String tradeUploadsOnSave(String duration, String size) {
    final template = _read('tradeUploadsOnSave');
    if (template == null) return _en.tradeUploadsOnSave(duration, size);
    return _fill(template, <String, Object?>{'duration': duration, 'size': size});
  }

  @override
  String get tradeVoiceNote => _read('tradeVoiceNote') ?? _en.tradeVoiceNote;

  @override
  String get tradeScreenshots => _read('tradeScreenshots') ?? _en.tradeScreenshots;

  @override
  String get tradeVoiceNotes => _read('tradeVoiceNotes') ?? _en.tradeVoiceNotes;

  @override
  String get tradeRemoveFileTitle => _read('tradeRemoveFileTitle') ?? _en.tradeRemoveFileTitle;

  @override
  String get tradeRemoveFileBody => _read('tradeRemoveFileBody') ?? _en.tradeRemoveFileBody;

  @override
  String get tradeRemove => _read('tradeRemove') ?? _en.tradeRemove;

  @override
  String get tradeTags => _read('tradeTags') ?? _en.tradeTags;

  @override
  String get tradeNoTags => _read('tradeNoTags') ?? _en.tradeNoTags;

  @override
  String get tradeAddTagHint => _read('tradeAddTagHint') ?? _en.tradeAddTagHint;

  @override
  String get tradeLiveTicket => _read('tradeLiveTicket') ?? _en.tradeLiveTicket;

  @override
  String get tradeEstimatedPnl => _read('tradeEstimatedPnl') ?? _en.tradeEstimatedPnl;

  @override
  String tradePips(String pips) {
    final template = _read('tradePips');
    if (template == null) return _en.tradePips(pips);
    return _fill(template, <String, Object?>{'pips': pips});
  }

  @override
  String get tradeRequired => _read('tradeRequired') ?? _en.tradeRequired;

  @override
  String get tradeNumber => _read('tradeNumber') ?? _en.tradeNumber;

  @override
  String get tradeMustBePositive => _read('tradeMustBePositive') ?? _en.tradeMustBePositive;

  @override
  String get tradeLevelsHint => _read('tradeLevelsHint') ?? _en.tradeLevelsHint;

  @override
  String get tradeLevelBuyStop => _read('tradeLevelBuyStop') ?? _en.tradeLevelBuyStop;

  @override
  String get tradeLevelBuyTake => _read('tradeLevelBuyTake') ?? _en.tradeLevelBuyTake;

  @override
  String get tradeLevelSellStop => _read('tradeLevelSellStop') ?? _en.tradeLevelSellStop;

  @override
  String get tradeLevelSellTake => _read('tradeLevelSellTake') ?? _en.tradeLevelSellTake;

  @override
  String get riskLabel => _read('riskLabel') ?? _en.riskLabel;

  @override
  String get riskRewardLabel => _read('riskRewardLabel') ?? _en.riskRewardLabel;

  @override
  String get riskHintEmpty => _read('riskHintEmpty') ?? _en.riskHintEmpty;

  @override
  String get riskStopWrongBuy => _read('riskStopWrongBuy') ?? _en.riskStopWrongBuy;

  @override
  String get riskStopWrongSell => _read('riskStopWrongSell') ?? _en.riskStopWrongSell;

  @override
  String get riskTakeWrongBuy => _read('riskTakeWrongBuy') ?? _en.riskTakeWrongBuy;

  @override
  String get riskTakeWrongSell => _read('riskTakeWrongSell') ?? _en.riskTakeWrongSell;

  @override
  String tradeLoadFailed(String message) {
    final template = _read('tradeLoadFailed');
    if (template == null) return _en.tradeLoadFailed(message);
    return _fill(template, <String, Object?>{'message': message});
  }

  @override
  String tradeSaveFailed(String message) {
    final template = _read('tradeSaveFailed');
    if (template == null) return _en.tradeSaveFailed(message);
    return _fill(template, <String, Object?>{'message': message});
  }

  @override
  String get tradeSaveTimedOut => _read('tradeSaveTimedOut') ?? _en.tradeSaveTimedOut;

  @override
  String get tradeMediaSavedNote => _read('tradeMediaSavedNote') ?? _en.tradeMediaSavedNote;

  @override
  String get tradeExitBeforeEntryError => _read('tradeExitBeforeEntryError') ?? _en.tradeExitBeforeEntryError;

  @override
  String get tradeSessionExpired => _read('tradeSessionExpired') ?? _en.tradeSessionExpired;

  @override
  String get tradeEnterEntryAndSize => _read('tradeEnterEntryAndSize') ?? _en.tradeEnterEntryAndSize;

  @override
  String get tradeSetOpenedTime => _read('tradeSetOpenedTime') ?? _en.tradeSetOpenedTime;

  @override
  String get tradePickSymbolFirst => _read('tradePickSymbolFirst') ?? _en.tradePickSymbolFirst;

  @override
  String get tradeOpenedInFuture => _read('tradeOpenedInFuture') ?? _en.tradeOpenedInFuture;

  @override
  String get tradeEnterEntryFirst => _read('tradeEnterEntryFirst') ?? _en.tradeEnterEntryFirst;

  @override
  String get tradePickSymbolToFindExit => _read('tradePickSymbolToFindExit') ?? _en.tradePickSymbolToFindExit;

  @override
  String get tradeNoCandles => _read('tradeNoCandles') ?? _en.tradeNoCandles;

  @override
  String get tradeCandlesUnreadable => _read('tradeCandlesUnreadable') ?? _en.tradeCandlesUnreadable;

  @override
  String tradeRemovePendingFailed(String message) {
    final template = _read('tradeRemovePendingFailed');
    if (template == null) return _en.tradeRemovePendingFailed(message);
    return _fill(template, <String, Object?>{'message': message});
  }

  @override
  String tradeRemoveFailed(String message) {
    final template = _read('tradeRemoveFailed');
    if (template == null) return _en.tradeRemoveFailed(message);
    return _fill(template, <String, Object?>{'message': message});
  }

  @override
  String get tradeRecordingOpenFailed => _read('tradeRecordingOpenFailed') ?? _en.tradeRecordingOpenFailed;

  @override
  String get tradeRecordingPlayFailed => _read('tradeRecordingPlayFailed') ?? _en.tradeRecordingPlayFailed;

  @override
  String journalRefreshFailed(String message) {
    final template = _read('journalRefreshFailed');
    if (template == null) return _en.journalRefreshFailed(message);
    return _fill(template, <String, Object?>{'message': message});
  }

  @override
  String journalRescueBanner(int count) {
    final template = _read('journalRescueBanner');
    if (template == null) return _en.journalRescueBanner(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String journalRowLine(String date, String entry, String exit, String lots) {
    final template = _read('journalRowLine');
    if (template == null) return _en.journalRowLine(date, entry, exit, lots);
    return _fill(template, <String, Object?>{'date': date, 'entry': entry, 'exit': exit, 'lots': lots});
  }

  @override
  String get journalResult => _read('journalResult') ?? _en.journalResult;
}
