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
  String get closeLabel => _read('closeLabel') ?? _en.closeLabel;

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
  String get loginFooterEncrypted => _read('loginFooterEncrypted') ?? _en.loginFooterEncrypted;

  @override
  String get termsLabel => _read('termsLabel') ?? _en.termsLabel;

  @override
  String get privacyLabel => _read('privacyLabel') ?? _en.privacyLabel;

  @override
  String get orSeparator => _read('orSeparator') ?? _en.orSeparator;

  @override
  String get forgotPassword => _read('forgotPassword') ?? _en.forgotPassword;

  @override
  String get resetTitle => _read('resetTitle') ?? _en.resetTitle;

  @override
  String get resetBody => _read('resetBody') ?? _en.resetBody;

  @override
  String get resetSend => _read('resetSend') ?? _en.resetSend;

  @override
  String resetSent(String email) {
    final template = _read('resetSent');
    if (template == null) return _en.resetSent(email);
    return _fill(template, <String, Object?>{'email': email});
  }

  @override
  String get resetFailed => _read('resetFailed') ?? _en.resetFailed;

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

  @override
  String syncedOne(String symbol, String pnl) {
    final template = _read('syncedOne');
    if (template == null) return _en.syncedOne(symbol, pnl);
    return _fill(template, <String, Object?>{'symbol': symbol, 'pnl': pnl});
  }

  @override
  String syncedMany(int count, String pnl) {
    final template = _read('syncedMany');
    if (template == null) return _en.syncedMany(count, pnl);
    return _fill(template, <String, Object?>{'count': count, 'pnl': pnl});
  }

  @override
  String journaledTitle(String symbol) {
    final template = _read('journaledTitle');
    if (template == null) return _en.journaledTitle(symbol);
    return _fill(template, <String, Object?>{'symbol': symbol});
  }

  @override
  String get journaledBody => _read('journaledBody') ?? _en.journaledBody;

  @override
  String get aTrade => _read('aTrade') ?? _en.aTrade;

  @override
  String get calendarPreviousMonth => _read('calendarPreviousMonth') ?? _en.calendarPreviousMonth;

  @override
  String get calendarNextMonth => _read('calendarNextMonth') ?? _en.calendarNextMonth;

  @override
  String get calendarNoTrades => _read('calendarNoTrades') ?? _en.calendarNoTrades;

  @override
  String calendarMonthFoot(String pnl, int trades, int days) {
    final template = _read('calendarMonthFoot');
    if (template == null) return _en.calendarMonthFoot(pnl, trades, days);
    return _fill(template, <String, Object?>{'pnl': pnl, 'trades': trades, 'days': days});
  }

  @override
  String get calendarLoadFailed => _read('calendarLoadFailed') ?? _en.calendarLoadFailed;

  @override
  String get calendarLegendWin => _read('calendarLegendWin') ?? _en.calendarLegendWin;

  @override
  String get calendarLegendLoss => _read('calendarLegendLoss') ?? _en.calendarLegendLoss;

  @override
  String get calendarDayEmpty => _read('calendarDayEmpty') ?? _en.calendarDayEmpty;

  @override
  String get symbolSearchHint => _read('symbolSearchHint') ?? _en.symbolSearchHint;

  @override
  String get symbolNoMatchTitle => _read('symbolNoMatchTitle') ?? _en.symbolNoMatchTitle;

  @override
  String get symbolNoMatchBody => _read('symbolNoMatchBody') ?? _en.symbolNoMatchBody;

  @override
  String symbolFooter(int count) {
    final template = _read('symbolFooter');
    if (template == null) return _en.symbolFooter(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get timeFrameTitle => _read('timeFrameTitle') ?? _en.timeFrameTitle;

  @override
  String get timeFrameNotServed => _read('timeFrameNotServed') ?? _en.timeFrameNotServed;

  @override
  String get screenshotFailed => _read('screenshotFailed') ?? _en.screenshotFailed;

  @override
  String get confirmTitle => _read('confirmTitle') ?? _en.confirmTitle;

  @override
  String confirmBody(String email) {
    final template = _read('confirmBody');
    if (template == null) return _en.confirmBody(email);
    return _fill(template, <String, Object?>{'email': email});
  }

  @override
  String get confirmChecked => _read('confirmChecked') ?? _en.confirmChecked;

  @override
  String get confirmCheckFailed => _read('confirmCheckFailed') ?? _en.confirmCheckFailed;

  @override
  String get confirmResent => _read('confirmResent') ?? _en.confirmResent;

  @override
  String get confirmResendFailed => _read('confirmResendFailed') ?? _en.confirmResendFailed;

  @override
  String get confirmCheckedAction => _read('confirmCheckedAction') ?? _en.confirmCheckedAction;

  @override
  String get confirmResendAction => _read('confirmResendAction') ?? _en.confirmResendAction;

  @override
  String get confirmOtherAccount => _read('confirmOtherAccount') ?? _en.confirmOtherAccount;

  @override
  String get edgeLoadFailed => _read('edgeLoadFailed') ?? _en.edgeLoadFailed;

  @override
  String get edgeWhenYouWin => _read('edgeWhenYouWin') ?? _en.edgeWhenYouWin;

  @override
  String get edgeIntro => _read('edgeIntro') ?? _en.edgeIntro;

  @override
  String edgeZonePill(String zone) {
    final template = _read('edgeZonePill');
    if (template == null) return _en.edgeZonePill(zone);
    return _fill(template, <String, Object?>{'zone': zone});
  }

  @override
  String get edgeEmptyTitle => _read('edgeEmptyTitle') ?? _en.edgeEmptyTitle;

  @override
  String get edgeEmptyBody => _read('edgeEmptyBody') ?? _en.edgeEmptyBody;

  @override
  String get edgeGroupTimeOfDay => _read('edgeGroupTimeOfDay') ?? _en.edgeGroupTimeOfDay;

  @override
  String get edgeGroupSessions => _read('edgeGroupSessions') ?? _en.edgeGroupSessions;

  @override
  String get edgeBestHour => _read('edgeBestHour') ?? _en.edgeBestHour;

  @override
  String get edgeWorstHour => _read('edgeWorstHour') ?? _en.edgeWorstHour;

  @override
  String get edgeBestSession => _read('edgeBestSession') ?? _en.edgeBestSession;

  @override
  String get edgeWorstSession => _read('edgeWorstSession') ?? _en.edgeWorstSession;

  @override
  String get edgeByHourTitle => _read('edgeByHourTitle') ?? _en.edgeByHourTitle;

  @override
  String get edgeByHourSub => _read('edgeByHourSub') ?? _en.edgeByHourSub;

  @override
  String edgeExcluded(int min, String median, int timed) {
    final template = _read('edgeExcluded');
    if (template == null) return _en.edgeExcluded(min, median, timed);
    return _fill(template, <String, Object?>{'min': min, 'median': median, 'timed': timed});
  }

  @override
  String get edgeSessionsSub => _read('edgeSessionsSub') ?? _en.edgeSessionsSub;

  @override
  String edgeNeedTrades(int min) {
    final template = _read('edgeNeedTrades');
    if (template == null) return _en.edgeNeedTrades(min);
    return _fill(template, <String, Object?>{'min': min});
  }

  @override
  String get edgeNotEnoughSample => _read('edgeNotEnoughSample') ?? _en.edgeNotEnoughSample;

  @override
  String edgeCardFoot(int trades, String winRate) {
    final template = _read('edgeCardFoot');
    if (template == null) return _en.edgeCardFoot(trades, winRate);
    return _fill(template, <String, Object?>{'trades': trades, 'winRate': winRate});
  }

  @override
  String get toolLong => _read('toolLong') ?? _en.toolLong;

  @override
  String get toolShort => _read('toolShort') ?? _en.toolShort;

  @override
  String get toolTrendLine => _read('toolTrendLine') ?? _en.toolTrendLine;

  @override
  String get toolRay => _read('toolRay') ?? _en.toolRay;

  @override
  String get toolVertical => _read('toolVertical') ?? _en.toolVertical;

  @override
  String get toolRectangle => _read('toolRectangle') ?? _en.toolRectangle;

  @override
  String get toolEllipse => _read('toolEllipse') ?? _en.toolEllipse;

  @override
  String get toolFibRetracement => _read('toolFibRetracement') ?? _en.toolFibRetracement;

  @override
  String get toolFibExtension => _read('toolFibExtension') ?? _en.toolFibExtension;

  @override
  String get toolMeasure => _read('toolMeasure') ?? _en.toolMeasure;

  @override
  String get toolText => _read('toolText') ?? _en.toolText;

  @override
  String get toolArrowUp => _read('toolArrowUp') ?? _en.toolArrowUp;

  @override
  String get toolArrowDown => _read('toolArrowDown') ?? _en.toolArrowDown;

  @override
  String get toolBrush => _read('toolBrush') ?? _en.toolBrush;

  @override
  String get catAll => _read('catAll') ?? _en.catAll;

  @override
  String get catPositions => _read('catPositions') ?? _en.catPositions;

  @override
  String get catTrend => _read('catTrend') ?? _en.catTrend;

  @override
  String get catShapes => _read('catShapes') ?? _en.catShapes;

  @override
  String get catFib => _read('catFib') ?? _en.catFib;

  @override
  String get catNotes => _read('catNotes') ?? _en.catNotes;

  @override
  String get catMeasure => _read('catMeasure') ?? _en.catMeasure;

  @override
  String get toolsSearchHint => _read('toolsSearchHint') ?? _en.toolsSearchHint;

  @override
  String toolsNoMatch(String query) {
    final template = _read('toolsNoMatch');
    if (template == null) return _en.toolsNoMatch(query);
    return _fill(template, <String, Object?>{'query': query});
  }

  @override
  String get toolsPinnedHeader => _read('toolsPinnedHeader') ?? _en.toolsPinnedHeader;

  @override
  String get toolsPinHint => _read('toolsPinHint') ?? _en.toolsPinHint;

  @override
  String get toolsUnpinHint => _read('toolsUnpinHint') ?? _en.toolsUnpinHint;

  @override
  String toolsPinnedA11y(String tool) {
    final template = _read('toolsPinnedA11y');
    if (template == null) return _en.toolsPinnedA11y(tool);
    return _fill(template, <String, Object?>{'tool': tool});
  }

  @override
  String toolsPinnedNotice(String tool) {
    final template = _read('toolsPinnedNotice');
    if (template == null) return _en.toolsPinnedNotice(tool);
    return _fill(template, <String, Object?>{'tool': tool});
  }

  @override
  String toolsUnpinnedNotice(String tool) {
    final template = _read('toolsUnpinnedNotice');
    if (template == null) return _en.toolsUnpinnedNotice(tool);
    return _fill(template, <String, Object?>{'tool': tool});
  }

  @override
  String get magnetLabel => _read('magnetLabel') ?? _en.magnetLabel;

  @override
  String get magnetOff => _read('magnetOff') ?? _en.magnetOff;

  @override
  String get magnetWeak => _read('magnetWeak') ?? _en.magnetWeak;

  @override
  String get magnetStrong => _read('magnetStrong') ?? _en.magnetStrong;

  @override
  String get continuousLabel => _read('continuousLabel') ?? _en.continuousLabel;

  @override
  String get switchOn => _read('switchOn') ?? _en.switchOn;

  @override
  String get switchOff => _read('switchOff') ?? _en.switchOff;

  @override
  String get closeAction => _read('closeAction') ?? _en.closeAction;

  @override
  String get chartToolsTitle => _read('chartToolsTitle') ?? _en.chartToolsTitle;

  @override
  String get chartToolsBody => _read('chartToolsBody') ?? _en.chartToolsBody;

  @override
  String get selectedObject => _read('selectedObject') ?? _en.selectedObject;

  @override
  String get objectEdit => _read('objectEdit') ?? _en.objectEdit;

  @override
  String get objectEditSub => _read('objectEditSub') ?? _en.objectEditSub;

  @override
  String get objectClone => _read('objectClone') ?? _en.objectClone;

  @override
  String get objectCloneSub => _read('objectCloneSub') ?? _en.objectCloneSub;

  @override
  String get objectDelete => _read('objectDelete') ?? _en.objectDelete;

  @override
  String get objectDeleteSub => _read('objectDeleteSub') ?? _en.objectDeleteSub;

  @override
  String get manageSection => _read('manageSection') ?? _en.manageSection;

  @override
  String get undoLast => _read('undoLast') ?? _en.undoLast;

  @override
  String get redoAction => _read('redoAction') ?? _en.redoAction;

  @override
  String get objectTree => _read('objectTree') ?? _en.objectTree;

  @override
  String get analysisHub => _read('analysisHub') ?? _en.analysisHub;

  @override
  String get analysisHubSub => _read('analysisHubSub') ?? _en.analysisHubSub;

  @override
  String get clearDrawings => _read('clearDrawings') ?? _en.clearDrawings;

  @override
  String get deskToday => _read('deskToday') ?? _en.deskToday;

  @override
  String get deskThisWeek => _read('deskThisWeek') ?? _en.deskThisWeek;

  @override
  String get deskMonthTrades => _read('deskMonthTrades') ?? _en.deskMonthTrades;

  @override
  String get rMultipleTitle => _read('rMultipleTitle') ?? _en.rMultipleTitle;

  @override
  String rMultipleSubtitle(int count) {
    final template = _read('rMultipleSubtitle');
    if (template == null) return _en.rMultipleSubtitle(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get rMultipleEmptyTitle => _read('rMultipleEmptyTitle') ?? _en.rMultipleEmptyTitle;

  @override
  String get rMultipleEmptyBody => _read('rMultipleEmptyBody') ?? _en.rMultipleEmptyBody;

  @override
  String rMultipleFoot(String average) {
    final template = _read('rMultipleFoot');
    if (template == null) return _en.rMultipleFoot(average);
    return _fill(template, <String, Object?>{'average': average});
  }

  @override
  String get strategyLeaderboard => _read('strategyLeaderboard') ?? _en.strategyLeaderboard;

  @override
  String get strategyLeaderboardSub => _read('strategyLeaderboardSub') ?? _en.strategyLeaderboardSub;

  @override
  String get sessionHeatmap => _read('sessionHeatmap') ?? _en.sessionHeatmap;

  @override
  String get sessionHeatmapSub => _read('sessionHeatmapSub') ?? _en.sessionHeatmapSub;

  @override
  String get symbolFavorites => _read('symbolFavorites') ?? _en.symbolFavorites;

  @override
  String get daySummaryTitle => _read('daySummaryTitle') ?? _en.daySummaryTitle;

  @override
  String get daySummaryHint => _read('daySummaryHint') ?? _en.daySummaryHint;

  @override
  String get daySummaryViewTrades => _read('daySummaryViewTrades') ?? _en.daySummaryViewTrades;

  @override
  String get symbolPickerTitle => _read('symbolPickerTitle') ?? _en.symbolPickerTitle;

  @override
  String get allAssets => _read('allAssets') ?? _en.allAssets;

  @override
  String get symbolNoFavoritesTitle => _read('symbolNoFavoritesTitle') ?? _en.symbolNoFavoritesTitle;

  @override
  String get symbolNoFavoritesBody => _read('symbolNoFavoritesBody') ?? _en.symbolNoFavoritesBody;

  @override
  String get pin => _read('pin') ?? _en.pin;

  @override
  String get unpin => _read('unpin') ?? _en.unpin;

  @override
  String get keepAction => _read('keepAction') ?? _en.keepAction;

  @override
  String get doneAction => _read('doneAction') ?? _en.doneAction;

  @override
  String get importTitle => _read('importTitle') ?? _en.importTitle;

  @override
  String get importUnreadableFile => _read('importUnreadableFile') ?? _en.importUnreadableFile;

  @override
  String importFileTooLarge(String size) {
    final template = _read('importFileTooLarge');
    if (template == null) return _en.importFileTooLarge(size);
    return _fill(template, <String, Object?>{'size': size});
  }

  @override
  String get importNoClosedTrades => _read('importNoClosedTrades') ?? _en.importNoClosedTrades;

  @override
  String get importNoReadableData => _read('importNoReadableData') ?? _en.importNoReadableData;

  @override
  String get importUnknownFile => _read('importUnknownFile') ?? _en.importUnknownFile;

  @override
  String get importDeleteTitle => _read('importDeleteTitle') ?? _en.importDeleteTitle;

  @override
  String importDeleteBody(int count, String filename) {
    final template = _read('importDeleteBody');
    if (template == null) return _en.importDeleteBody(count, filename);
    return _fill(template, <String, Object?>{'count': count, 'filename': filename});
  }

  @override
  String importDeleted(int count) {
    final template = _read('importDeleted');
    if (template == null) return _en.importDeleted(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get importImporting => _read('importImporting') ?? _en.importImporting;

  @override
  String importAction(int count) {
    final template = _read('importAction');
    if (template == null) return _en.importAction(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get importChooseAnother => _read('importChooseAnother') ?? _en.importChooseAnother;

  @override
  String get importReadingFile => _read('importReadingFile') ?? _en.importReadingFile;

  @override
  String get importChooseFile => _read('importChooseFile') ?? _en.importChooseFile;

  @override
  String get importFileTypes => _read('importFileTypes') ?? _en.importFileTypes;

  @override
  String get importSkippedNote => _read('importSkippedNote') ?? _en.importSkippedNote;

  @override
  String get importSelectedFile => _read('importSelectedFile') ?? _en.importSelectedFile;

  @override
  String get importNoTradesFound => _read('importNoTradesFound') ?? _en.importNoTradesFound;

  @override
  String importFileStats(int trades, int wins, int losses) {
    final template = _read('importFileStats');
    if (template == null) return _en.importFileStats(trades, wins, losses);
    return _fill(template, <String, Object?>{'trades': trades, 'wins': wins, 'losses': losses});
  }

  @override
  String get importRemoveFile => _read('importRemoveFile') ?? _en.importRemoveFile;

  @override
  String get importNetPnl => _read('importNetPnl') ?? _en.importNetPnl;

  @override
  String get importDateRange => _read('importDateRange') ?? _en.importDateRange;

  @override
  String get importPreview => _read('importPreview') ?? _en.importPreview;

  @override
  String importPreviewSub(int shown, int total) {
    final template = _read('importPreviewSub');
    if (template == null) return _en.importPreviewSub(shown, total);
    return _fill(template, <String, Object?>{'shown': shown, 'total': total});
  }

  @override
  String importPreviewLine(String type, String lot) {
    final template = _read('importPreviewLine');
    if (template == null) return _en.importPreviewLine(type, lot);
    return _fill(template, <String, Object?>{'type': type, 'lot': lot});
  }

  @override
  String get importNothingNew => _read('importNothingNew') ?? _en.importNothingNew;

  @override
  String get importComplete => _read('importComplete') ?? _en.importComplete;

  @override
  String importAlreadyInJournal(int count) {
    final template = _read('importAlreadyInJournal');
    if (template == null) return _en.importAlreadyInJournal(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String importAdded(int count) {
    final template = _read('importAdded');
    if (template == null) return _en.importAdded(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String importDuplicatesSkipped(int count) {
    final template = _read('importDuplicatesSkipped');
    if (template == null) return _en.importDuplicatesSkipped(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get importAnother => _read('importAnother') ?? _en.importAnother;

  @override
  String get importClearBody => _read('importClearBody') ?? _en.importClearBody;

  @override
  String get importClearAction => _read('importClearAction') ?? _en.importClearAction;

  @override
  String get importJournalCleared => _read('importJournalCleared') ?? _en.importJournalCleared;

  @override
  String get importHistoryTitle => _read('importHistoryTitle') ?? _en.importHistoryTitle;

  @override
  String get importHistorySub => _read('importHistorySub') ?? _en.importHistorySub;

  @override
  String get importHistoryEmpty => _read('importHistoryEmpty') ?? _en.importHistoryEmpty;

  @override
  String importHistoryLine(int count, String when) {
    final template = _read('importHistoryLine');
    if (template == null) return _en.importHistoryLine(count, when);
    return _fill(template, <String, Object?>{'count': count, 'when': when});
  }

  @override
  String get importDeleteTooltip => _read('importDeleteTooltip') ?? _en.importDeleteTooltip;

  @override
  String get importHowToTitle => _read('importHowToTitle') ?? _en.importHowToTitle;

  @override
  String get importHowToSteps => _read('importHowToSteps') ?? _en.importHowToSteps;

  @override
  String get importNetNote => _read('importNetNote') ?? _en.importNetNote;

  @override
  String get syncTitle => _read('syncTitle') ?? _en.syncTitle;

  @override
  String get syncSubmitting => _read('syncSubmitting') ?? _en.syncSubmitting;

  @override
  String get syncDisconnectTitle => _read('syncDisconnectTitle') ?? _en.syncDisconnectTitle;

  @override
  String get syncDisconnectBody => _read('syncDisconnectBody') ?? _en.syncDisconnectBody;

  @override
  String get syncDisconnectAction => _read('syncDisconnectAction') ?? _en.syncDisconnectAction;

  @override
  String get syncNotYet => _read('syncNotYet') ?? _en.syncNotYet;

  @override
  String syncSecondsAgo(int count) {
    final template = _read('syncSecondsAgo');
    if (template == null) return _en.syncSecondsAgo(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String syncMinutesAgo(int count) {
    final template = _read('syncMinutesAgo');
    if (template == null) return _en.syncMinutesAgo(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String syncHoursAgo(int count) {
    final template = _read('syncHoursAgo');
    if (template == null) return _en.syncHoursAgo(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String syncDaysAgo(int count) {
    final template = _read('syncDaysAgo');
    if (template == null) return _en.syncDaysAgo(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get syncStatusConnected => _read('syncStatusConnected') ?? _en.syncStatusConnected;

  @override
  String get syncStatusConnecting => _read('syncStatusConnecting') ?? _en.syncStatusConnecting;

  @override
  String get syncStatusFailed => _read('syncStatusFailed') ?? _en.syncStatusFailed;

  @override
  String get syncStatusDisconnected => _read('syncStatusDisconnected') ?? _en.syncStatusDisconnected;

  @override
  String get syncCurrent => _read('syncCurrent') ?? _en.syncCurrent;

  @override
  String get syncBroker => _read('syncBroker') ?? _en.syncBroker;

  @override
  String get syncServer => _read('syncServer') ?? _en.syncServer;

  @override
  String get syncAccount => _read('syncAccount') ?? _en.syncAccount;

  @override
  String get syncLastTrade => _read('syncLastTrade') ?? _en.syncLastTrade;

  @override
  String get syncHintConnected => _read('syncHintConnected') ?? _en.syncHintConnected;

  @override
  String syncHintStalledError(String error) {
    final template = _read('syncHintStalledError');
    if (template == null) return _en.syncHintStalledError(error);
    return _fill(template, <String, Object?>{'error': error});
  }

  @override
  String get syncHintStalledConnecting => _read('syncHintStalledConnecting') ?? _en.syncHintStalledConnecting;

  @override
  String get syncHintStalled => _read('syncHintStalled') ?? _en.syncHintStalled;

  @override
  String get syncHintConnecting => _read('syncHintConnecting') ?? _en.syncHintConnecting;

  @override
  String get syncHintPending => _read('syncHintPending') ?? _en.syncHintPending;

  @override
  String get syncMailFailed => _read('syncMailFailed') ?? _en.syncMailFailed;

  @override
  String get syncContactSupport => _read('syncContactSupport') ?? _en.syncContactSupport;

  @override
  String get syncDisconnectLong => _read('syncDisconnectLong') ?? _en.syncDisconnectLong;

  @override
  String get syncSearchBrokers => _read('syncSearchBrokers') ?? _en.syncSearchBrokers;

  @override
  String get syncDemo => _read('syncDemo') ?? _en.syncDemo;

  @override
  String get syncLive => _read('syncLive') ?? _en.syncLive;

  @override
  String syncLastAttempt(String details) {
    final template = _read('syncLastAttempt');
    if (template == null) return _en.syncLastAttempt(details);
    return _fill(template, <String, Object?>{'details': details});
  }

  @override
  String get syncConnectTitle => _read('syncConnectTitle') ?? _en.syncConnectTitle;

  @override
  String get syncConnectBody => _read('syncConnectBody') ?? _en.syncConnectBody;

  @override
  String get syncAccountNumber => _read('syncAccountNumber') ?? _en.syncAccountNumber;

  @override
  String get syncInvestorPassword => _read('syncInvestorPassword') ?? _en.syncInvestorPassword;

  @override
  String get syncInvestorNote => _read('syncInvestorNote') ?? _en.syncInvestorNote;

  @override
  String get syncConnectAction => _read('syncConnectAction') ?? _en.syncConnectAction;

  @override
  String get syncAfterConnect => _read('syncAfterConnect') ?? _en.syncAfterConnect;

  @override
  String get syncUseTyped => _read('syncUseTyped') ?? _en.syncUseTyped;

  @override
  String get syncBrokersUnavailableTitle => _read('syncBrokersUnavailableTitle') ?? _en.syncBrokersUnavailableTitle;

  @override
  String get syncBrokersUnavailableBody => _read('syncBrokersUnavailableBody') ?? _en.syncBrokersUnavailableBody;

  @override
  String get syncTypeServer => _read('syncTypeServer') ?? _en.syncTypeServer;

  @override
  String syncBrokerCount(int count) {
    final template = _read('syncBrokerCount');
    if (template == null) return _en.syncBrokerCount(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get backtestTitle => _read('backtestTitle') ?? _en.backtestTitle;

  @override
  String get backtestIntro => _read('backtestIntro') ?? _en.backtestIntro;

  @override
  String get backtestCustom => _read('backtestCustom') ?? _en.backtestCustom;

  @override
  String get backtestFileUnreadable => _read('backtestFileUnreadable') ?? _en.backtestFileUnreadable;

  @override
  String get backtestFileTooLarge => _read('backtestFileTooLarge') ?? _en.backtestFileTooLarge;

  @override
  String get backtestNeedData => _read('backtestNeedData') ?? _en.backtestNeedData;

  @override
  String get backtestRunSaved => _read('backtestRunSaved') ?? _en.backtestRunSaved;

  @override
  String get backtestRunUnsaved => _read('backtestRunUnsaved') ?? _en.backtestRunUnsaved;

  @override
  String get backtestRunFailed => _read('backtestRunFailed') ?? _en.backtestRunFailed;

  @override
  String get backtestLoadRunFailed => _read('backtestLoadRunFailed') ?? _en.backtestLoadRunFailed;

  @override
  String get backtestDeleteTitle => _read('backtestDeleteTitle') ?? _en.backtestDeleteTitle;

  @override
  String get backtestThisRun => _read('backtestThisRun') ?? _en.backtestThisRun;

  @override
  String get backtestRunDeleted => _read('backtestRunDeleted') ?? _en.backtestRunDeleted;

  @override
  String get backtestDeleteFailed => _read('backtestDeleteFailed') ?? _en.backtestDeleteFailed;

  @override
  String get backtestSimulating => _read('backtestSimulating') ?? _en.backtestSimulating;

  @override
  String get backtestRunAction => _read('backtestRunAction') ?? _en.backtestRunAction;

  @override
  String get backtestBarsTitle => _read('backtestBarsTitle') ?? _en.backtestBarsTitle;

  @override
  String get backtestChooseCsv => _read('backtestChooseCsv') ?? _en.backtestChooseCsv;

  @override
  String get clearAction => _read('clearAction') ?? _en.clearAction;

  @override
  String get backtestBarsHint => _read('backtestBarsHint') ?? _en.backtestBarsHint;

  @override
  String get backtestRulesTitle => _read('backtestRulesTitle') ?? _en.backtestRulesTitle;

  @override
  String get backtestRunName => _read('backtestRunName') ?? _en.backtestRunName;

  @override
  String get backtestRunNameHint => _read('backtestRunNameHint') ?? _en.backtestRunNameHint;

  @override
  String get backtestSymbol => _read('backtestSymbol') ?? _en.backtestSymbol;

  @override
  String get backtestTimeframe => _read('backtestTimeframe') ?? _en.backtestTimeframe;

  @override
  String get backtestRulesLabel => _read('backtestRulesLabel') ?? _en.backtestRulesLabel;

  @override
  String get backtestCompiledRules => _read('backtestCompiledRules') ?? _en.backtestCompiledRules;

  @override
  String get backtestUseBuiltIn => _read('backtestUseBuiltIn') ?? _en.backtestUseBuiltIn;

  @override
  String get backtestCostsTitle => _read('backtestCostsTitle') ?? _en.backtestCostsTitle;

  @override
  String get backtestStartingBalance => _read('backtestStartingBalance') ?? _en.backtestStartingBalance;

  @override
  String get backtestRiskPercent => _read('backtestRiskPercent') ?? _en.backtestRiskPercent;

  @override
  String get backtestContractSize => _read('backtestContractSize') ?? _en.backtestContractSize;

  @override
  String get backtestMaxLeverage => _read('backtestMaxLeverage') ?? _en.backtestMaxLeverage;

  @override
  String get backtestSpread => _read('backtestSpread') ?? _en.backtestSpread;

  @override
  String get backtestSlippage => _read('backtestSlippage') ?? _en.backtestSlippage;

  @override
  String get backtestCommission => _read('backtestCommission') ?? _en.backtestCommission;

  @override
  String get backtestInSampleShare => _read('backtestInSampleShare') ?? _en.backtestInSampleShare;

  @override
  String get backtestClockOffset => _read('backtestClockOffset') ?? _en.backtestClockOffset;

  @override
  String get backtestEmptyTitle => _read('backtestEmptyTitle') ?? _en.backtestEmptyTitle;

  @override
  String get backtestEmptyBody => _read('backtestEmptyBody') ?? _en.backtestEmptyBody;

  @override
  String get backtestReturn => _read('backtestReturn') ?? _en.backtestReturn;

  @override
  String get backtestSharpe => _read('backtestSharpe') ?? _en.backtestSharpe;

  @override
  String get backtestExposure => _read('backtestExposure') ?? _en.backtestExposure;

  @override
  String get backtestAvgR => _read('backtestAvgR') ?? _en.backtestAvgR;

  @override
  String backtestBarsLine(String bars, String range, String timeframe) {
    final template = _read('backtestBarsLine');
    if (template == null) return _en.backtestBarsLine(bars, range, timeframe);
    return _fill(template, <String, Object?>{'bars': bars, 'range': range, 'timeframe': timeframe});
  }

  @override
  String get backtestEquity => _read('backtestEquity') ?? _en.backtestEquity;

  @override
  String get backtestSplitTitle => _read('backtestSplitTitle') ?? _en.backtestSplitTitle;

  @override
  String get backtestSplitBody => _read('backtestSplitBody') ?? _en.backtestSplitBody;

  @override
  String get backtestColWindow => _read('backtestColWindow') ?? _en.backtestColWindow;

  @override
  String get backtestColTrades => _read('backtestColTrades') ?? _en.backtestColTrades;

  @override
  String get backtestColNet => _read('backtestColNet') ?? _en.backtestColNet;

  @override
  String get backtestColWin => _read('backtestColWin') ?? _en.backtestColWin;

  @override
  String get backtestColMaxDd => _read('backtestColMaxDd') ?? _en.backtestColMaxDd;

  @override
  String get backtestInSample => _read('backtestInSample') ?? _en.backtestInSample;

  @override
  String get backtestOutOfSample => _read('backtestOutOfSample') ?? _en.backtestOutOfSample;

  @override
  String get backtestAssumptions => _read('backtestAssumptions') ?? _en.backtestAssumptions;

  @override
  String backtestTradesTitle(int count) {
    final template = _read('backtestTradesTitle');
    if (template == null) return _en.backtestTradesTitle(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get backtestColSide => _read('backtestColSide') ?? _en.backtestColSide;

  @override
  String get backtestColEntry => _read('backtestColEntry') ?? _en.backtestColEntry;

  @override
  String get backtestColLots => _read('backtestColLots') ?? _en.backtestColLots;

  @override
  String get backtestColPnl => _read('backtestColPnl') ?? _en.backtestColPnl;

  @override
  String get backtestColWhy => _read('backtestColWhy') ?? _en.backtestColWhy;

  @override
  String get backtestSavedRuns => _read('backtestSavedRuns') ?? _en.backtestSavedRuns;

  @override
  String get backtestSavedSub => _read('backtestSavedSub') ?? _en.backtestSavedSub;

  @override
  String get backtestNoSavedRuns => _read('backtestNoSavedRuns') ?? _en.backtestNoSavedRuns;

  @override
  String backtestRunFallback(String symbol) {
    final template = _read('backtestRunFallback');
    if (template == null) return _en.backtestRunFallback(symbol);
    return _fill(template, <String, Object?>{'symbol': symbol});
  }

  @override
  String backtestDeleteTooltip(String name) {
    final template = _read('backtestDeleteTooltip');
    if (template == null) return _en.backtestDeleteTooltip(name);
    return _fill(template, <String, Object?>{'name': name});
  }

  @override
  String get cbIntro => _read('cbIntro') ?? _en.cbIntro;

  @override
  String get cbGalleryFailed => _read('cbGalleryFailed') ?? _en.cbGalleryFailed;

  @override
  String get cbUseImage => _read('cbUseImage') ?? _en.cbUseImage;

  @override
  String cbReadFailed(String name) {
    final template = _read('cbReadFailed');
    if (template == null) return _en.cbReadFailed(name);
    return _fill(template, <String, Object?>{'name': name});
  }

  @override
  String cbTooManyCharts(int max) {
    final template = _read('cbTooManyCharts');
    if (template == null) return _en.cbTooManyCharts(max);
    return _fill(template, <String, Object?>{'max': max});
  }

  @override
  String get cbChartTooLarge => _read('cbChartTooLarge') ?? _en.cbChartTooLarge;

  @override
  String get cbChartsBudget => _read('cbChartsBudget') ?? _en.cbChartsBudget;

  @override
  String get cbNothingRecorded => _read('cbNothingRecorded') ?? _en.cbNothingRecorded;

  @override
  String get cbVoiceAdded => _read('cbVoiceAdded') ?? _en.cbVoiceAdded;

  @override
  String get cbRecordingFailed => _read('cbRecordingFailed') ?? _en.cbRecordingFailed;

  @override
  String get cbDescribeFirst => _read('cbDescribeFirst') ?? _en.cbDescribeFirst;

  @override
  String get cbCompileFailed => _read('cbCompileFailed') ?? _en.cbCompileFailed;

  @override
  String get cbStepSetup => _read('cbStepSetup') ?? _en.cbStepSetup;

  @override
  String get cbDescriptionHint => _read('cbDescriptionHint') ?? _en.cbDescriptionHint;

  @override
  String get cbSymbolOptional => _read('cbSymbolOptional') ?? _en.cbSymbolOptional;

  @override
  String get cbStopOptional => _read('cbStopOptional') ?? _en.cbStopOptional;

  @override
  String get cbCriteriaLabel => _read('cbCriteriaLabel') ?? _en.cbCriteriaLabel;

  @override
  String get cbCompiling => _read('cbCompiling') ?? _en.cbCompiling;

  @override
  String get cbCompileAction => _read('cbCompileAction') ?? _en.cbCompileAction;

  @override
  String get cbNoChartsSent => _read('cbNoChartsSent') ?? _en.cbNoChartsSent;

  @override
  String cbChartsSent(int count) {
    final template = _read('cbChartsSent');
    if (template == null) return _en.cbChartsSent(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String cbRulesLine(String timeframe, String charts) {
    final template = _read('cbRulesLine');
    if (template == null) return _en.cbRulesLine(timeframe, charts);
    return _fill(template, <String, Object?>{'timeframe': timeframe, 'charts': charts});
  }

  @override
  String cbCompiledWith(String model) {
    final template = _read('cbCompiledWith');
    if (template == null) return _en.cbCompiledWith(model);
    return _fill(template, <String, Object?>{'model': model});
  }

  @override
  String get cbUseRules => _read('cbUseRules') ?? _en.cbUseRules;

  @override
  String get cbCompileAgain => _read('cbCompileAgain') ?? _en.cbCompileAgain;

  @override
  String get cbAddChart => _read('cbAddChart') ?? _en.cbAddChart;

  @override
  String cbAddChartCount(int current, int max) {
    final template = _read('cbAddChartCount');
    if (template == null) return _en.cbAddChartCount(current, max);
    return _fill(template, <String, Object?>{'current': current, 'max': max});
  }

  @override
  String cbStopRecording(int seconds) {
    final template = _read('cbStopRecording');
    if (template == null) return _en.cbStopRecording(seconds);
    return _fill(template, <String, Object?>{'seconds': seconds});
  }

  @override
  String get cbTranscribing => _read('cbTranscribing') ?? _en.cbTranscribing;

  @override
  String get cbVoiceNote => _read('cbVoiceNote') ?? _en.cbVoiceNote;

  @override
  String cbAttachmentsNote(int max) {
    final template = _read('cbAttachmentsNote');
    if (template == null) return _en.cbAttachmentsNote(max);
    return _fill(template, <String, Object?>{'max': max});
  }

  @override
  String get cbTimeframe => _read('cbTimeframe') ?? _en.cbTimeframe;

  @override
  String get cbConfirmation => _read('cbConfirmation') ?? _en.cbConfirmation;

  @override
  String get cbNone => _read('cbNone') ?? _en.cbNone;

  @override
  String get chartDrawingTools => _read('chartDrawingTools') ?? _en.chartDrawingTools;

  @override
  String get chartMarketReplay => _read('chartMarketReplay') ?? _en.chartMarketReplay;

  @override
  String get chartStyle => _read('chartStyle') ?? _en.chartStyle;

  @override
  String chartMagnetTooltip(String mode) {
    final template = _read('chartMagnetTooltip');
    if (template == null) return _en.chartMagnetTooltip(mode);
    return _fill(template, <String, Object?>{'mode': mode});
  }

  @override
  String get chartHideBuySell => _read('chartHideBuySell') ?? _en.chartHideBuySell;

  @override
  String get chartBuySell => _read('chartBuySell') ?? _en.chartBuySell;

  @override
  String chartTitle(String symbol) {
    final template = _read('chartTitle');
    if (template == null) return _en.chartTitle(symbol);
    return _fill(template, <String, Object?>{'symbol': symbol});
  }

  @override
  String get chartFullscreen => _read('chartFullscreen') ?? _en.chartFullscreen;

  @override
  String get chartExitFullscreen => _read('chartExitFullscreen') ?? _en.chartExitFullscreen;

  @override
  String get chartExitTimeBeforeEntry => _read('chartExitTimeBeforeEntry') ?? _en.chartExitTimeBeforeEntry;

  @override
  String get chartHeadsUp => _read('chartHeadsUp') ?? _en.chartHeadsUp;

  @override
  String get chartDragLevel => _read('chartDragLevel') ?? _en.chartDragLevel;

  @override
  String get chartCrosshairOn => _read('chartCrosshairOn') ?? _en.chartCrosshairOn;

  @override
  String get chartCrosshairOff => _read('chartCrosshairOff') ?? _en.chartCrosshairOff;

  @override
  String get chartStopBuyBelow => _read('chartStopBuyBelow') ?? _en.chartStopBuyBelow;

  @override
  String get chartStopSellAbove => _read('chartStopSellAbove') ?? _en.chartStopSellAbove;

  @override
  String get chartTargetBuyAbove => _read('chartTargetBuyAbove') ?? _en.chartTargetBuyAbove;

  @override
  String get chartTargetSellBelow => _read('chartTargetSellBelow') ?? _en.chartTargetSellBelow;

  @override
  String get chartUnreachableAccount => _read('chartUnreachableAccount') ?? _en.chartUnreachableAccount;

  @override
  String chartIntervalRefused(String interval) {
    final template = _read('chartIntervalRefused');
    if (template == null) return _en.chartIntervalRefused(interval);
    return _fill(template, <String, Object?>{'interval': interval});
  }

  @override
  String get chartNoCandlesWindow => _read('chartNoCandlesWindow') ?? _en.chartNoCandlesWindow;

  @override
  String get chartPlacementMove => _read('chartPlacementMove') ?? _en.chartPlacementMove;

  @override
  String get chartPlacementLift => _read('chartPlacementLift') ?? _en.chartPlacementLift;

  @override
  String get chartPlacementTapFirst => _read('chartPlacementTapFirst') ?? _en.chartPlacementTapFirst;

  @override
  String get chartPlacementTap => _read('chartPlacementTap') ?? _en.chartPlacementTap;

  @override
  String chartPlacedOfTotal(int placed, int total) {
    final template = _read('chartPlacedOfTotal');
    if (template == null) return _en.chartPlacedOfTotal(placed, total);
    return _fill(template, <String, Object?>{'placed': placed, 'total': total});
  }

  @override
  String chartMagnetSuffix(String mode) {
    final template = _read('chartMagnetSuffix');
    if (template == null) return _en.chartMagnetSuffix(mode);
    return _fill(template, <String, Object?>{'mode': mode});
  }

  @override
  String get chartKeepDrawingOn => _read('chartKeepDrawingOn') ?? _en.chartKeepDrawingOn;

  @override
  String get chartKeepDrawingOff => _read('chartKeepDrawingOff') ?? _en.chartKeepDrawingOff;

  @override
  String get chartPutToolAway => _read('chartPutToolAway') ?? _en.chartPutToolAway;

  @override
  String get chartMoreActions => _read('chartMoreActions') ?? _en.chartMoreActions;

  @override
  String get chartClone => _read('chartClone') ?? _en.chartClone;

  @override
  String get chartColour => _read('chartColour') ?? _en.chartColour;

  @override
  String get chartLineWidth => _read('chartLineWidth') ?? _en.chartLineWidth;

  @override
  String get chartLineStyle => _read('chartLineStyle') ?? _en.chartLineStyle;

  @override
  String get chartLock => _read('chartLock') ?? _en.chartLock;

  @override
  String get chartUnlock => _read('chartUnlock') ?? _en.chartUnlock;

  @override
  String get chartShow => _read('chartShow') ?? _en.chartShow;

  @override
  String get chartHide => _read('chartHide') ?? _en.chartHide;

  @override
  String get chartRemove => _read('chartRemove') ?? _en.chartRemove;

  @override
  String chartAddAlertAt(String symbol, String price) {
    final template = _read('chartAddAlertAt');
    if (template == null) return _en.chartAddAlertAt(symbol, price);
    return _fill(template, <String, Object?>{'symbol': symbol, 'price': price});
  }

  @override
  String get chartAlertSubtitle => _read('chartAlertSubtitle') ?? _en.chartAlertSubtitle;

  @override
  String get chartPinLevel => _read('chartPinLevel') ?? _en.chartPinLevel;

  @override
  String get chartPinSubtitle => _read('chartPinSubtitle') ?? _en.chartPinSubtitle;

  @override
  String get chartUseAsEntry => _read('chartUseAsEntry') ?? _en.chartUseAsEntry;

  @override
  String get chartUseAsEntrySub => _read('chartUseAsEntrySub') ?? _en.chartUseAsEntrySub;

  @override
  String get chartCopyPrice => _read('chartCopyPrice') ?? _en.chartCopyPrice;

  @override
  String chartAlertSet(String price) {
    final template = _read('chartAlertSet');
    if (template == null) return _en.chartAlertSet(price);
    return _fill(template, <String, Object?>{'price': price});
  }

  @override
  String chartLevelPinned(String price) {
    final template = _read('chartLevelPinned');
    if (template == null) return _en.chartLevelPinned(price);
    return _fill(template, <String, Object?>{'price': price});
  }

  @override
  String chartPriceCopied(String price) {
    final template = _read('chartPriceCopied');
    if (template == null) return _en.chartPriceCopied(price);
    return _fill(template, <String, Object?>{'price': price});
  }

  @override
  String get chartReplayFromDate => _read('chartReplayFromDate') ?? _en.chartReplayFromDate;

  @override
  String chartNoCandlesFor(String date) {
    final template = _read('chartNoCandlesFor');
    if (template == null) return _en.chartNoCandlesFor(date);
    return _fill(template, <String, Object?>{'date': date});
  }

  @override
  String chartFeedDown(String at) {
    final template = _read('chartFeedDown');
    if (template == null) return _en.chartFeedDown(at);
    return _fill(template, <String, Object?>{'at': at});
  }

  @override
  String get chartNoEarlierCandles => _read('chartNoEarlierCandles') ?? _en.chartNoEarlierCandles;

  @override
  String get chartProIntervals => _read('chartProIntervals') ?? _en.chartProIntervals;

  @override
  String get chartBasicIntervals => _read('chartBasicIntervals') ?? _en.chartBasicIntervals;

  @override
  String get chartPinUpgrade => _read('chartPinUpgrade') ?? _en.chartPinUpgrade;

  @override
  String get chartReplayUpgrade => _read('chartReplayUpgrade') ?? _en.chartReplayUpgrade;

  @override
  String get chartLoadEarlier => _read('chartLoadEarlier') ?? _en.chartLoadEarlier;

  @override
  String get chartPreviousBar => _read('chartPreviousBar') ?? _en.chartPreviousBar;

  @override
  String get chartNextBar => _read('chartNextBar') ?? _en.chartNextBar;

  @override
  String get chartPauseReplay => _read('chartPauseReplay') ?? _en.chartPauseReplay;

  @override
  String get chartPlayReplay => _read('chartPlayReplay') ?? _en.chartPlayReplay;

  @override
  String get chartJumpToDate => _read('chartJumpToDate') ?? _en.chartJumpToDate;

  @override
  String get chartExitReplay => _read('chartExitReplay') ?? _en.chartExitReplay;

  @override
  String get chartNoteHint => _read('chartNoteHint') ?? _en.chartNoteHint;

  @override
  String get chartAdd => _read('chartAdd') ?? _en.chartAdd;

  @override
  String get chartAlertLine => _read('chartAlertLine') ?? _en.chartAlertLine;

  @override
  String get chartAlertLineFired => _read('chartAlertLineFired') ?? _en.chartAlertLineFired;

  @override
  String chartTextWith(String body) {
    final template = _read('chartTextWith');
    if (template == null) return _en.chartTextWith(body);
    return _fill(template, <String, Object?>{'body': body});
  }

  @override
  String chartPositionSummary(String entry, String stop, String target, String risk) {
    final template = _read('chartPositionSummary');
    if (template == null) return _en.chartPositionSummary(entry, stop, target, risk);
    return _fill(template, <String, Object?>{'entry': entry, 'stop': stop, 'target': target, 'risk': risk});
  }

  @override
  String get chartObjectLockedBody => _read('chartObjectLockedBody') ?? _en.chartObjectLockedBody;

  @override
  String get chartObjectUnlockedBody => _read('chartObjectUnlockedBody') ?? _en.chartObjectUnlockedBody;

  @override
  String get chartHideBody => _read('chartHideBody') ?? _en.chartHideBody;

  @override
  String chartObjectsOnChart(int count) {
    final template = _read('chartObjectsOnChart');
    if (template == null) return _en.chartObjectsOnChart(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get chartObjectHidden => _read('chartObjectHidden') ?? _en.chartObjectHidden;

  @override
  String get chartUndoAction => _read('chartUndoAction') ?? _en.chartUndoAction;

  @override
  String get chartWorkspace => _read('chartWorkspace') ?? _en.chartWorkspace;

  @override
  String get chartToolsLabel => _read('chartToolsLabel') ?? _en.chartToolsLabel;

  @override
  String get chartNoLayoutSaved => _read('chartNoLayoutSaved') ?? _en.chartNoLayoutSaved;

  @override
  String chartLayoutName(String name) {
    final template = _read('chartLayoutName');
    if (template == null) return _en.chartLayoutName(name);
    return _fill(template, <String, Object?>{'name': name});
  }

  @override
  String get chartLayouts => _read('chartLayouts') ?? _en.chartLayouts;

  @override
  String chartLayoutsSaved(int count) {
    final template = _read('chartLayoutsSaved');
    if (template == null) return _en.chartLayoutsSaved(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get chartSettings => _read('chartSettings') ?? _en.chartSettings;

  @override
  String get chartSaveShort => _read('chartSaveShort') ?? _en.chartSaveShort;

  @override
  String get chartThisChart => _read('chartThisChart') ?? _en.chartThisChart;

  @override
  String get chartOpen => _read('chartOpen') ?? _en.chartOpen;

  @override
  String get chartFromLibrary => _read('chartFromLibrary') ?? _en.chartFromLibrary;

  @override
  String get chartNew => _read('chartNew') ?? _en.chartNew;

  @override
  String get chartBlankChart => _read('chartBlankChart') ?? _en.chartBlankChart;

  @override
  String get chartType => _read('chartType') ?? _en.chartType;

  @override
  String get chartIndicators => _read('chartIndicators') ?? _en.chartIndicators;

  @override
  String get chartNone => _read('chartNone') ?? _en.chartNone;

  @override
  String chartStudiesOn(int count) {
    final template = _read('chartStudiesOn');
    if (template == null) return _en.chartStudiesOn(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get chartAlerts => _read('chartAlerts') ?? _en.chartAlerts;

  @override
  String get chartLevelTouches => _read('chartLevelTouches') ?? _en.chartLevelTouches;

  @override
  String get chartReplay => _read('chartReplay') ?? _en.chartReplay;

  @override
  String chartObjectsShort(int count) {
    final template = _read('chartObjectsShort');
    if (template == null) return _en.chartObjectsShort(count);
    return _fill(template, <String, Object?>{'count': count});
  }

  @override
  String get chartTimeZone => _read('chartTimeZone') ?? _en.chartTimeZone;

  @override
  String get chartEvents => _read('chartEvents') ?? _en.chartEvents;

  @override
  String get chartSaveLayoutTitle => _read('chartSaveLayoutTitle') ?? _en.chartSaveLayoutTitle;

  @override
  String get chartUpdateLayoutTitle => _read('chartUpdateLayoutTitle') ?? _en.chartUpdateLayoutTitle;

  @override
  String get chartLayoutNameLabel => _read('chartLayoutNameLabel') ?? _en.chartLayoutNameLabel;

  @override
  String get chartSave => _read('chartSave') ?? _en.chartSave;

  @override
  String get chartUpdate => _read('chartUpdate') ?? _en.chartUpdate;

  @override
  String chartSavedName(String name) {
    final template = _read('chartSavedName');
    if (template == null) return _en.chartSavedName(name);
    return _fill(template, <String, Object?>{'name': name});
  }

  @override
  String chartOpenedLayout(String name) {
    final template = _read('chartOpenedLayout');
    if (template == null) return _en.chartOpenedLayout(name);
    return _fill(template, <String, Object?>{'name': name});
  }

  @override
  String chartOpenedLayoutOn(String name, String symbol) {
    final template = _read('chartOpenedLayoutOn');
    if (template == null) return _en.chartOpenedLayoutOn(name, symbol);
    return _fill(template, <String, Object?>{'name': name, 'symbol': symbol});
  }

  @override
  String get chartA11yQuickActions => _read('chartA11yQuickActions') ?? _en.chartA11yQuickActions;

  @override
  String get chartA11yFitScale => _read('chartA11yFitScale') ?? _en.chartA11yFitScale;

  @override
  String get chartA11yFinishDrawing => _read('chartA11yFinishDrawing') ?? _en.chartA11yFinishDrawing;

  @override
  String get chartTimeZoneTitle => _read('chartTimeZoneTitle') ?? _en.chartTimeZoneTitle;

  @override
  String get chartSearchZone => _read('chartSearchZone') ?? _en.chartSearchZone;
}
