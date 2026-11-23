import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/features.dart';
import '../core/subscription.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/models.dart';
import '../services/alerts.dart';
import '../services/journal_api.dart';
import '../ui/language_picker.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ui/zone_clock.dart';
import 'alerts_screen.dart';
import 'rules_screen.dart';
import 'subscription_screen.dart';
import 'sync_screen.dart';
import 'package:mtl_trader_mobile/core/friendly_error.dart';

/// IANA names that Postgres can resolve with `AT TIME ZONE`.
const List<String> _timezoneOptions = [
  'UTC',
  'Europe/London',
  'Europe/Dublin',
  'Europe/Lisbon',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Amsterdam',
  'Europe/Stockholm',
  'Europe/Warsaw',
  'Europe/Athens',
  'Europe/Istanbul',
  'Europe/Moscow',
  'Africa/Lagos',
  'Africa/Johannesburg',
  'Africa/Nairobi',
  'Africa/Cairo',
  'Asia/Dubai',
  'Asia/Karachi',
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Bangkok',
  'Asia/Singapore',
  'Asia/Hong_Kong',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Perth',
  'Australia/Sydney',
  'Pacific/Auckland',
  'America/Sao_Paulo',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Toronto',
  'America/Mexico_City',
];

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.api,
    this.onProfileChanged,
    this.onOpenImport,
    this.onOpenBacktest,
    this.onOpenPropFirm,
  });

  final JournalApi api;

  /// Lets the shell rebuild the desk, journal and edge tabs after a setting
  /// that changes their data (currently the report timezone).
  final VoidCallback? onProfileChanged;

  /// Opens the phone import screen. Supplied by the shell, because importing
  /// has to reload the other tabs afterwards.
  final VoidCallback? onOpenImport;

  /// Opens the backtest workbench. Kept here beside import: both are set up from
  /// the account tab rather than adding a sixth destination to the bar.
  final VoidCallback? onOpenBacktest;

  /// Opens the prop-firm evaluation. It has its own screen instead of a card on
  /// the desk, so the rule headroom is not buried among the dashboard tiles.
  final VoidCallback? onOpenPropFirm;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  /// Read through the State's own context: most of this screen's text is built
  /// in helper methods rather than inside `build`.
  AppLocalizations get _l10n => AppLocalizations.of(context);

  late Future<Map<String, dynamic>> _future;

  /// The account's reporting timezone; the app bar clock and the reminder
  /// picker both speak it. Mirrored into state because the app bar is built
  /// outside the profile FutureBuilder.
  String _zoneId = 'UTC';

  String _lockMode = 'off';
  double _lossLimit = 0;
  int _maxTrades = 0;
  bool _lockLoading = true;

  @override
  void initState() {
    super.initState();
    _future = widget.api.profile();
    _future.then((profile) {
      if (!mounted) return;
      final zone = asString(profile['timezone']);
      if (zone != null && zone != _zoneId) setState(() => _zoneId = zone);
    }).catchError((_) {
      // The clock keeps the last known zone; the body reports the failure.
    });
    _loadDailyStop();
  }

  Future<void> _loadDailyStop() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('playbooks')
          .select('lock_mode, daily_loss_limit, max_trades_per_day')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _lockMode = (row?['lock_mode'] as String?) ?? 'off';
        _lossLimit = (row?['daily_loss_limit'] as num?)?.toDouble() ?? 0;
        _maxTrades = (row?['max_trades_per_day'] as num?)?.toInt() ?? 0;
        _lockLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _lockLoading = false);
    }
  }

  /// Opens the rules editor. The phone has no sixth tab to spare, and the rules
  /// are where a session starts, so they live one tap from here.
  Future<void> _openRules() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RulesScreen()),
    );
    if (!mounted) return;
    setState(() => _lockLoading = true);
    await _loadDailyStop();
  }

  String _money(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  /// The daily stop, summarised. The budget, the cap and the lock mode are
  /// edited in Rules, so this card can never disagree with the screen the web
  /// app shows or with the gate that enforces it.
  Widget _dailyStopCard() {
    final configured = _lossLimit > 0 || _maxTrades > 0;
    final lockLabel = switch (_lockMode) {
      'soft' => _l10n.lockSoft,
      'hard' => _l10n.lockHard,
      _ => _l10n.lockJournalOnly,
    };
    final detail = !configured
        ? _l10n.accountStopNone
        : switch (_lockMode) {
            'soft' => _l10n.accountStopSoft,
            'hard' => _l10n.accountStopHard,
            _ => _l10n.accountStopOff,
          };

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.accountDailyStop,
            subtitle:
                _l10n.accountDailyStopBody,
          ),
          const SizedBox(height: 10),
          if (_lockLoading)
            Text(
              _l10n.accountLoadingRules,
              style: TextStyle(color: AppColors.faint, fontSize: 11.5),
            )
          else ...[
            LabelValue(
              label: _l10n.accountLossBudget,
              value: _lossLimit > 0 ? _money(_lossLimit) : _l10n.accountOff,
            ),
            const ListDivider(),
            LabelValue(
              label: _l10n.accountMaxEntries,
              value: _maxTrades > 0 ? '$_maxTrades' : _l10n.accountNoCap,
            ),
            const ListDivider(),
            LabelValue(label: _l10n.accountWhenReached, value: lockLabel),
            const SizedBox(height: 8),
            Text(
              detail,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openRules,
              icon: const Icon(Icons.rule_outlined, size: 16),
              label: Text(_l10n.accountEditRules),
            ),
          ),
        ],
      ),
    );
  }

  /// A quiet grouping label. The account tab holds every setting the app has,
  /// so the sections matter more than the individual cards.
  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: AppColors.faint,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
      );

  Widget _navTile({
    required IconData icon,
    required String label,
    String? detail,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (detail != null)
              Text(
                detail,
                style: TextStyle(color: AppColors.faint, fontSize: 11),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: AppColors.faint),
            ],
          ],
        ),
      ),
    );
  }

  /// The set-up-once tools: rules, the broker link, an import, the backtester
  /// and the prop evaluation. They are navigation, not settings, so they stay
  /// together instead of competing with the buttons a trader taps weekly.
  Widget _tradingCard() {
    final tiles = <Widget>[
      _navTile(
        icon: Icons.rule_outlined,
        label: _l10n.accountRules,
        onTap: _openRules,
      ),
      if (kMt5SyncEnabled)
        _navTile(
          icon: Icons.sync,
          label: _l10n.accountConnectMt5,
          onTap: _openSync,
        ),
      if (widget.onOpenImport != null)
        _navTile(
          icon: Icons.upload_file,
          label: _l10n.accountImport,
          onTap: widget.onOpenImport,
        ),
      if (widget.onOpenBacktest != null)
        _navTile(
          icon: Icons.science_outlined,
          label: _l10n.accountBacktest,
          onTap: widget.onOpenBacktest,
        ),
      if (widget.onOpenPropFirm != null)
        _navTile(
          icon: Icons.verified_user_outlined,
          label: _l10n.accountPropFirm,
          onTap: widget.onOpenPropFirm,
        ),
    ];

    return FlatCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < tiles.length; index++) ...[
            tiles[index],
            if (index != tiles.length - 1) const ListDivider(),
          ],
        ],
      ),
    );
  }

  Widget _timezoneCard(String timezone) {
    return FlatCard(
      padding: EdgeInsets.zero,
      child: _navTile(
        icon: Icons.public,
        label: _l10n.accountTimezoneRow,
        detail: timezone,
        onTap: () => _pickTimezone(timezone),
      ),
    );
  }

  /// The three alerts this phone can raise, plus the reminder time and the way
  /// into the list of what has already fired.
  ///
  /// They are switches rather than toggles on a server setting because they are
  /// device behaviour: the phone posts them itself, with no push service, and a
  /// trader who turns one off expects it to stop on this phone only.
  /// Asking here rather than at launch puts the Android permission dialog in
  /// front of the three switches that need it, which is the only moment the
  /// request explains itself.
  bool _askedForAlerts = false;

  Widget _alertsCard() {
    final alerts = Alerts.instance;
    if (!_askedForAlerts) {
      _askedForAlerts = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final granted = await Alerts.instance.ensurePermission();
        if (mounted && granted) setState(() {});
      });
    }
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.alertsSection,
            subtitle: _l10n.alertsBody,
          ),
          const SizedBox(height: 6),
          _alertSwitch(
            icon: Icons.shield_outlined,
            title: _l10n.alertsDailyStop,
            body: _l10n.alertsDailyStopBody,
            value: alerts.dailyStopEnabled,
            onChanged: (value) async {
              await alerts.setDailyStop(value);
              setState(() {});
            },
          ),
          _alertSwitch(
            icon: Icons.show_chart,
            title: _l10n.alertsLevels,
            body: _l10n.alertsLevelsBody,
            value: alerts.levelsEnabled,
            onChanged: (value) async {
              await alerts.setLevels(value);
              setState(() {});
            },
          ),
          _alertSwitch(
            icon: Icons.edit_note,
            title: _l10n.alertsJournal,
            body: _l10n.alertsJournalBody,
            value: alerts.journalEnabled,
            onChanged: (value) async {
              await alerts.setJournal(value);
              setState(() {});
            },
          ),
          if (alerts.journalEnabled)
            InkWell(
              onTap: () async {
                // The picker edits the time in the account's zone; the alert
                // service stores the UTC instant it names.
                final current = alerts.reminderAtIn(_zoneId);
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: current.hour,
                    minute: current.minute,
                  ),
                  helpText: _l10n.alertsReminderAt,
                );
                if (picked == null) return;
                await alerts.setJournal(
                  true,
                  atInZone: TimeOfDayValue(picked.hour, picked.minute),
                  zoneId: _zoneId,
                );
                if (mounted) setState(() {});
              },
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: AppColors.faint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _l10n.alertsReminderAt,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      alerts.reminderAtIn(_zoneId).label,
                      style: tabular.copyWith(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const ListDivider(),
          const AlertsSummary(),
        ],
      ),
    );
  }

  Widget _alertSwitch({
    required IconData icon,
    required String title,
    required String body,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.faint),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    body,
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final next = widget.api.profile();
    setState(() => _future = next);
    try {
      final profile = await next;
      if (!mounted) return;
      final zone = asString(profile['timezone']);
      if (zone != null && zone != _zoneId) setState(() => _zoneId = zone);
    } catch (_) {
      // The empty profile still renders the signed-in email.
    }
  }

  Future<void> _openPlans() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionScreen(api: widget.api),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  /// The MT5 connection lives here rather than in the tab bar: it is set up once
  /// and then forgotten, unlike the desk, journal and analytics. Hidden while
  /// `kMt5SyncEnabled` is off; the screen itself is untouched.
  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncScreen(api: widget.api),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  /// Opens the mail app with the account address already in the body, so a
  /// support request arrives with a way to find the account.
  Future<void> _emailSupport() async {
    final account = Supabase.instance.client.auth.currentUser?.email ?? '';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@mtlledger.com',
      queryParameters: {
        'subject': 'MTL Ledger support',
        'body': 'Account: $account\n\nWhat happened:\n',
      },
    );
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      // Falls through to the message below. The address stays out of the UI.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_l10n.accountMailFailed)),
    );
  }

  /// The store listing in the browser. Play handles an already-reviewed account
  /// itself, which is why there is no review plugin to keep up to date.
  Future<void> _rateApp() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.mtltrader.app',
    );
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_l10n.accountStoreFailed)),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.accountSignOutQuestion),
        content: Text(
          _l10n.accountSignOutBody,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.api.signOut();
    }
  }

  Future<void> _pickTimezone(String current) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          _l10n.accountTimezoneDialog,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
          child: ListView(
            children: [
              for (final zone in _timezoneOptions)
                ListTile(
                  dense: true,
                  title: Text(
                    zone,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                    ),
                  ),
                  trailing: zone == current
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(dialogContext, zone),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_l10n.cancel),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;

    try {
      await widget.api.updateTimezone(selected);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.accountTimezoneSaved(selected))),
      );
      widget.onProfileChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.accountTimezoneFailed('$error'))),
      );
    }
  }

  /// A picture the user chose, stored on the auth record so it needs no
  /// migration and follows them across devices.
  String? get _avatarUrl {
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    final value = metadata?['avatar_url'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// The picture tied to the address, resolved by the web API so no MD5
  /// implementation ships in the app. Null when there is no usable address.
  String? _emailAvatarUrl(String email) {
    final address = email.trim();
    if (address.isEmpty || !address.contains('@')) return null;
    return '${AppConfig.apiBaseUrl}/api/avatar'
        '?email=${Uri.encodeQueryComponent(address)}&s=96';
  }

  Future<void> _editAvatar(String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          _l10n.accountPicture,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l10n.accountPictureBody,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://…'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_l10n.commonSave),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final value = controller.text.trim();
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'avatar_url': value.isEmpty ? null : value}),
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value.isEmpty
                ? _l10n.accountPictureCleared
                : _l10n.accountPictureUpdated,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.accountPictureFailed('$error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_l10n.account),
        actions: [ZoneClock(zoneId: _zoneId)],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final profile = snapshot.data ?? const <String, dynamic>{};
          final email = asString(profile['email']) ??
              widget.api.currentUser?.email ??
              _l10n.accountSignedIn;
          final name = asString(profile['full_name']);
          final timezone = asString(profile['timezone']) ?? 'UTC';
          // Resolved against the clock, not just the stored row: a period that
          // ended yesterday must read as ended even before the expiry job runs.
          final info = SubscriptionInfo.fromProfile(profile);

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
              children: [
                if (snapshot.hasError) ...[
                  FlatCard(
                    padding: const EdgeInsets.all(12),
                    borderColor: AppColors.danger.withAlpha(80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _l10n.accountSubError,
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          friendlyError(snapshot.error),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _refresh,
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(_l10n.commonTryAgain),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FlatCard(
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _editAvatar(_avatarUrl),
                        child: _Avatar(
                          url: _avatarUrl ?? _emailAvatarUrl(email),
                          initials: _initials(name, email),
                          size: 42,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name ?? email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.faint,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        text: info.planLabel.toUpperCase(),
                        tone: info.state == SubscriptionState.active
                            ? Tone.positive
                            : info.state == SubscriptionState.trial
                                ? Tone.neutral
                                : Tone.negative,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FlatCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
                        child: SectionTitle(title: _l10n.accountSubscription),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            LabelValue(
                              label: _l10n.accountPlan,
                              value: info.planLabel,
                            ),
                            const ListDivider(),
                            LabelValue(
                              label: _l10n.accountStatus,
                              value: info.statusLabel,
                              valueColor: info.hasAccess
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                            const ListDivider(),
                            LabelValue(
                              label: _l10n.accountTradeLimit,
                              value: info.maxTrades <= 0
                                  ? _l10n.accountUnlimited
                                  : '${info.maxTrades}',
                            ),
                            const ListDivider(),
                            LabelValue(
                              label: _l10n.accountTimezone,
                              value: timezone,
                              trailing: TextButton(
                                onPressed: () => _pickTimezone(timezone),
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(_l10n.accountChange),
                              ),
                            ),
                            if (info.state == SubscriptionState.trial &&
                                info.trialEndsAt != null) ...[
                              const ListDivider(),
                              LabelValue(
                                label: _l10n.accountTrialEnds,
                                value: DateFormat('d MMM yyyy')
                                    .format(info.trialEndsAt!),
                              ),
                            ],
                            if (info.state == SubscriptionState.active &&
                                info.periodEndsAt != null) ...[
                              const ListDivider(),
                              LabelValue(
                                label: info.cancelAtPeriodEnd
                                    ? _l10n.accountAccessUntil
                                    : _l10n.accountPaidThrough,
                                value: DateFormat('d MMM yyyy')
                                    .format(info.periodEndsAt!),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                if (info.ended) ...[
                  const SizedBox(height: 10),
                  FlatCard(
                    borderColor: AppColors.danger.withAlpha(110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.endedTitle,
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info.endedBody,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _openPlans,
                            child: Text(info.callToAction),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openPlans,
                  icon: const Icon(Icons.credit_card, size: 16),
                  label: Text(
                    info.hasAccess
                        ? _l10n.accountViewPlans
                        : _l10n.accountBuyPlan,
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel(_l10n.sectionTrading),
                _dailyStopCard(),
                const SizedBox(height: 8),
                _tradingCard(),
                const SizedBox(height: 16),
                _sectionLabel(_l10n.sectionPreferences),
                _timezoneCard(timezone),
                const SizedBox(height: 10),
                _alertsCard(),
                const SizedBox(height: 10),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        title: _l10n.accountAppearance,
                        subtitle:
                            _l10n.accountAppearanceBody,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final theme in AppTheme.values) ...[
                            _ThemeChoice(theme: theme),
                            if (theme != AppTheme.values.last)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const LanguagePicker(),
                const SizedBox(height: 16),
                _sectionLabel(_l10n.sectionSupport),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        title: _l10n.accountHelp,
                        subtitle:
                            _l10n.accountHelpBody,
                      ),
                      const SizedBox(height: 10),
                      // No address is shown. The button hands the mail app the
                      // destination, so support mail is one tap and the address
                      // is not on screen (or in a screenshot) for scrapers.
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _emailSupport,
                          icon: const Icon(Icons.mail_outline, size: 16),
                          label: Text(_l10n.accountEmailSupport),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _rateApp,
                          icon: const Icon(Icons.star_outline, size: 16),
                          label: Text(_l10n.accountRate),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Developer and behind-the-scenes detail, kept together at the
                // bottom instead of sitting at the same weight as the settings a
                // trader actually changes.
                _sectionLabel(_l10n.sectionAbout),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        title: _l10n.accountAbout,
                        subtitle: _l10n.accountAboutBody,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _l10n.accountPrivateMedia,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _l10n.accountPrivateMediaBody,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger),
                  ),
                  child: Text(_l10n.signOut),
                ),
                const SizedBox(height: 14),
                Text(
                  _l10n.accountFooter,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: kMinLabelSize,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _initials(String? name, String email) {
    final source = (name ?? '').trim().isNotEmpty ? name!.trim() : email.trim();
    if (source.isEmpty) return 'MT';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return source.length >= 2
        ? source.substring(0, 2).toUpperCase()
        : source.toUpperCase();
  }
}

/// Round profile picture with an initials fallback. A missing or unreachable
/// image falls back to the same tile the old design used, so the row never
/// collapses to a broken-image box.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.initials,
    required this.size,
  });

  final String? url;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(24),
        border: Border.all(color: AppColors.primary.withAlpha(80)),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.primaryLight,
          fontSize: size * 0.33,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final source = url;
    if (source == null || source.isEmpty) return placeholder;
    return ClipOval(
      child: Image.network(
        source,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

/// One of the four appearance options. The root rebuilds the tree when the
/// theme changes, so this needs no local state.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final active = ThemeController.instance.theme == theme;
    final l10n = AppLocalizations.of(context);
    final label = switch (theme) {
      AppTheme.dark => l10n.themeDark,
      AppTheme.light => l10n.themeLight,
      AppTheme.blue => l10n.themeBlue,
      AppTheme.system => l10n.themeSystem,
    };
    final icon = switch (theme) {
      AppTheme.dark => Icons.dark_mode_outlined,
      AppTheme.light => Icons.light_mode_outlined,
      AppTheme.blue => Icons.water_drop_outlined,
      AppTheme.system => Icons.brightness_auto_outlined,
    };

    return Expanded(
      child: InkWell(
        onTap: () => ThemeController.instance.setTheme(theme),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active ? AppColors.primary.withAlpha(20) : AppColors.surfaceAlt,
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.primary : AppColors.muted,
                  fontSize: kMinLabelSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

