// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'MTL Trader';

  @override
  String get retry => 'Réessayer';

  @override
  String get cancel => 'Annuler';

  @override
  String get refresh => 'Actualiser';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Système';

  @override
  String get navDesk => 'Bureau';

  @override
  String get navJournal => 'Journal';

  @override
  String get navAnalytics => 'Analyses';

  @override
  String get navCalendar => 'Calendrier';

  @override
  String get navAccount => 'Compte';

  @override
  String get newTrade => 'Consigner un trade';

  @override
  String get timeEdge => 'Edge horaire';

  @override
  String get brandName => 'MTL Trader';

  @override
  String get brandOpenPlans => 'MTL Trader — ouvrir les offres';

  @override
  String get loginHeadline => 'Le journal qui\nvous lit en retour.';

  @override
  String get loginTagline =>
      'Notez l\'exécution, la capture et la note vocale. Trouvez les heures qui paient.';

  @override
  String get continueWithGoogle => 'Continuer avec Google';

  @override
  String get signIn => 'Se connecter';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get emailLabel => 'E-mail';

  @override
  String get emailHint => 'vous@exemple.com';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get showPassword => 'Afficher le mot de passe';

  @override
  String get hidePassword => 'Masquer le mot de passe';

  @override
  String get emailInvalid => 'Saisissez une adresse e-mail valide.';

  @override
  String get passwordTooShort => 'Utilisez au moins 6 caractères.';

  @override
  String get loginFootnote =>
      'La connexion Google ne demande aucune confirmation. Les inscriptions par e-mail doivent confirmer l\'adresse avant l\'ouverture du journal.';

  @override
  String get googleOpenFailed =>
      'Impossible d\'ouvrir la connexion Google. Vérifiez qu\'un navigateur est disponible, puis réessayez.';

  @override
  String get googleTimedOut =>
      'La connexion Google a expiré. Vérifiez votre connexion et réessayez.';

  @override
  String get googleStartFailed =>
      'Impossible de démarrer la connexion Google. Réessayez.';

  @override
  String get signInUnreachable =>
      'Impossible de joindre le journal. Vérifiez votre connexion et réessayez.';

  @override
  String get googleFinishNotice =>
      'Terminez la connexion avec Google, puis revenez ici — le journal s\'ouvre tout seul.';

  @override
  String confirmEmailNotice(String email) {
    return 'Compte créé. Ouvrez le lien de confirmation reçu à $email, puis connectez-vous ici.';
  }

  @override
  String get accountBalance => 'Solde du compte';

  @override
  String get inProfit => 'En profit';

  @override
  String get inDrawdown => 'En drawdown';

  @override
  String get deposits => 'Dépôts';

  @override
  String get bestTrade => 'Meilleur trade';

  @override
  String get worstTrade => 'Pire trade';

  @override
  String netSummary(String pnl, int closed, int wins, int losses) {
    return '$pnl net · $closed clôturés · ${wins}G / ${losses}P';
  }

  @override
  String get importHistoryHint =>
      'Importez l\'historique pour tracer la courbe';

  @override
  String get winRate => 'Taux de réussite';

  @override
  String get profitFactor => 'Facteur de profit';

  @override
  String get maxDrawdown => 'Drawdown max';

  @override
  String get avgPerTrade => 'Moy. / trade';

  @override
  String winnersCount(int count) {
    return '$count gagnants';
  }

  @override
  String get peakToTrough => 'Du pic au creux';

  @override
  String get expectancy => 'Espérance';

  @override
  String get thisMonth => 'Ce mois';

  @override
  String monthTrades(int count) {
    return '$count trades';
  }

  @override
  String greenDays(int count) {
    return '$count jours verts';
  }

  @override
  String get monthWinRate => 'Réussite du mois';

  @override
  String timeEdgeSubtitle(String timezone, String hold) {
    return 'Heures d\'entrée en $timezone ; sessions en UTC. Durée médiane $hold.';
  }

  @override
  String get report => 'Rapport';

  @override
  String get noTimedTradesTitle => 'Aucun trade horodaté';

  @override
  String get noTimedTradesBody =>
      'Renseignez l\'heure d\'entrée et de sortie d\'un trade. Le rapport par heure et par session se construit à partir de cette plage.';

  @override
  String get mostProfitableHour => 'Heure la plus rentable';

  @override
  String get mostLosses => 'Le plus de pertes';

  @override
  String get bestSession => 'Meilleure session';

  @override
  String get weakestSession => 'Session la plus faible';

  @override
  String get needsMoreTrades => '3 trades minimum';

  @override
  String periodStats(int trades, String winRate) {
    return '$trades trades · $winRate de réussite';
  }

  @override
  String get thinSampleNote =>
      'Les heures avec moins de 3 trades sont exclues du meilleur et du pire.';

  @override
  String get journalSectionTitle => 'Journal';

  @override
  String get journalSectionSubtitle =>
      'Les notes, captures et notes vocales derrière chaque exécution.';

  @override
  String get nothingJournaledTitle => 'Rien de consigné';

  @override
  String get nothingJournaledBody =>
      'Ouvrez un trade et ajoutez une capture ou une note vocale — c\'est la fiche que vous relirez.';

  @override
  String get recentFills => 'Exécutions récentes';

  @override
  String get noFillsTitle => 'Aucune exécution';

  @override
  String get startHere => 'Commencez ici';

  @override
  String get startHeadline => 'Trois étapes pour un journal qui vous rapporte.';

  @override
  String get startStep1 =>
      'Importez l\'historique MT5 ou saisissez votre première exécution.';

  @override
  String get startStep2 =>
      'Ajoutez l\'heure d\'entrée et de sortie — c\'est ce qui alimente le rapport d\'edge.';

  @override
  String get startStep3 =>
      'Joignez la capture du graphique et une note vocale.';

  @override
  String get seeTimeReport => 'Voir le rapport horaire →';

  @override
  String get couldNotLoadDesk => 'Impossible de charger le bureau';

  @override
  String a11yProfit(String amount) {
    return 'Gain de $amount';
  }

  @override
  String a11yLoss(String amount) {
    return 'Perte de $amount';
  }

  @override
  String a11yBreakEven(String amount) {
    return 'Neutre, $amount';
  }

  @override
  String a11yEquityCurve(String change) {
    return 'Courbe d\'équité. $change depuis le premier jour enregistré.';
  }

  @override
  String get a11yHourChart => 'Profit et perte par heure d\'entrée.';

  @override
  String a11yScreenshots(int count) {
    return '$count captures jointes';
  }

  @override
  String a11yVoiceNotes(int count) {
    return '$count notes vocales jointes';
  }

  @override
  String get languageSubtitle =>
      'Les libellés, les mois et les dates suivent ce choix. Enregistré sur ce téléphone.';

  @override
  String get journalTitle => 'Journal';

  @override
  String get journalSearchHint =>
      'Rechercher un symbole, une stratégie ou un tag';

  @override
  String get journalSessionAll => 'Toutes les sessions';

  @override
  String get journalSessionAsian => 'Asie';

  @override
  String get journalSessionLondon => 'Londres';

  @override
  String get journalSessionNewYork => 'New York';

  @override
  String get journalSessionSydney => 'Sydney';

  @override
  String get journalFilterAll => 'Toutes';

  @override
  String get journalFilterWins => 'Gains';

  @override
  String get journalFilterLosses => 'Pertes';

  @override
  String get journalLoading => 'Chargement…';

  @override
  String journalCountSummary(int count, String pnl) {
    return '$count trades · $pnl';
  }

  @override
  String get journalLoadMore => 'Charger plus';

  @override
  String get journalClearMenu => 'Vider le journal';

  @override
  String get journalEmptyTitle => 'Aucun trade trouvé';

  @override
  String get journalEmptyBody =>
      'Touchez + pour consigner une exécution, ou importez votre historique MT5 depuis le bureau web.';

  @override
  String get journalErrorTitle => 'Impossible de charger le journal';

  @override
  String get deleteTradeTitle => 'Supprimer ce trade ?';

  @override
  String deleteTradeBody(String symbol) {
    return '$symbol ainsi que ses photos et notes vocales seront supprimés. Action irréversible.';
  }

  @override
  String get deleteAction => 'Supprimer';

  @override
  String get deleteDone => 'Trade supprimé.';

  @override
  String deleteFailed(String error) {
    return 'Impossible de supprimer le trade : $error';
  }

  @override
  String get clearJournalTitle => 'Vider le journal ?';

  @override
  String get clearJournalBody =>
      'Tous les trades, photos et notes vocales de ce compte seront supprimés. Action irréversible.';

  @override
  String get clearAllAction => 'Tout effacer';

  @override
  String clearFailed(String error) {
    return 'Impossible de vider le journal : $error';
  }

  @override
  String get analyticsEmptyTitle => 'Aucun trade à analyser';

  @override
  String get analyticsEmptyBody =>
      'Consignez quelques trades et les analyses se remplissent automatiquement.';

  @override
  String get analyticsErrorTitle => 'Impossible de charger les analyses';

  @override
  String get analyticsErrorBody => 'Vérifiez votre connexion et réessayez.';

  @override
  String get timeEdgeDescription =>
      'Meilleure et pire heure d\'entrée, sessions et courbe sur 24 heures.';

  @override
  String get performanceSummaryTitle => 'Résumé des performances';

  @override
  String get performanceSummarySubtitle =>
      'Tous les trades clôturés du journal.';

  @override
  String get summaryTrades => 'Trades';

  @override
  String summaryTradesFoot(int count) {
    return '$count ce mois';
  }

  @override
  String summaryWinLoss(int wins, int losses) {
    return '${wins}G · ${losses}P';
  }

  @override
  String summaryGrossFoot(String profit, String loss) {
    return 'Brut $profit / $loss';
  }

  @override
  String get summaryAverageTrade => 'Trade moyen';

  @override
  String summaryNetFoot(String net) {
    return 'Net $net';
  }

  @override
  String summaryBestTradeFoot(String worst) {
    return 'Pire $worst';
  }

  @override
  String summaryMonthFoot(int count) {
    return '$count jours gagnants';
  }

  @override
  String get monthlyPnlTitle => 'P&L mensuel';

  @override
  String get monthlyPnlSubtitle => 'Six derniers mois';

  @override
  String get pnlByDayTitle => 'P&L par jour';

  @override
  String get pnlByDayRecent => '30 derniers jours';

  @override
  String pnlByDayBestWorst(
      String bestDay, String bestPnl, String worstDay, String worstPnl) {
    return 'Meilleur $bestDay $bestPnl · Pire $worstDay $worstPnl';
  }

  @override
  String get legendLoss => 'Perte';

  @override
  String get legendNoTrades => 'Aucun trade';

  @override
  String get legendProfit => 'Profit';

  @override
  String get tapADay => 'Touchez un jour';

  @override
  String get performanceBySymbol => 'Performance par symbole';

  @override
  String get performanceBySymbolSubtitle => 'Trié par P&L net';

  @override
  String get performanceByTag => 'Performance par tag';

  @override
  String get performanceByTagSubtitle =>
      'Les tags ajoutés à un trade, regroupés.';

  @override
  String symbolStats(int trades, String winRate) {
    return '${trades}T · $winRate de réussite';
  }

  @override
  String tagStats(int trades, int wins, int losses, String winRate) {
    return '${trades}T · ${wins}G ${losses}P · $winRate';
  }

  @override
  String get a11yRunningCurve =>
      'Profit et perte cumulés des 30 derniers jours.';

  @override
  String a11yHeatmapDay(String day, String pnl, int trades) {
    return '$day : $pnl, $trades trades';
  }

  @override
  String a11yHeatmapEmpty(String day) {
    return '$day : aucun trade';
  }
}
