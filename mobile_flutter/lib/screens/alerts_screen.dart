import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/alerts.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Everything the phone has alerted on, newest first, with the reason each one
/// fired.
///
/// This is the part a notification cannot give: by the time you tap one the
/// banner is gone, and "why did I get this" is the question that matters. Each
/// row keeps the trigger that produced it, and an alert that was recorded while
/// its switch was off shows as not shown rather than disappearing.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<AlertEvent> _events = const [];
  bool _loading = true;
  bool _permitted = true;

  @override
  void initState() {
    super.initState();
    _load();
    Alerts.instance.revision.addListener(_load);
  }

  @override
  void dispose() {
    Alerts.instance.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final events = await Alerts.instance.history();
    final permitted = await Alerts.instance.permissionGranted();
    if (!mounted) return;
    setState(() {
      _events = events;
      _permitted = permitted;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.alertsTitle),
        actions: [
          if (_events.isNotEmpty)
            IconButton(
              tooltip: l10n.alertsClear,
              onPressed: () async {
                await Alerts.instance.clearHistory();
                await _load();
              },
              icon: Icon(Icons.delete_sweep_outlined, size: 20),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              children: [
                if (!_permitted) _permissionCard(l10n),
                if (_events.isEmpty)
                  _empty(l10n)
                else
                  for (final event in _events) ...[
                    _EventCard(event: event, l10n: l10n),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    final sent = await Alerts.instance.sendTest();
                    await _load();
                    if (!context.mounted) return;
                    if (!sent) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.alertsPermissionMissing)),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                  label: Text(l10n.alertsSendTest),
                ),
              ],
            ),
    );
  }

  Widget _permissionCard(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.danger.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.alertsPermissionMissing,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 40, 8, 30),
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 30, color: AppColors.faint),
          const SizedBox(height: 10),
          Text(
            l10n.alertsEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.alertsEmptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.l10n});

  final AlertEvent event;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (event.kind) {
      AlertKind.dailyStop => (Icons.shield_outlined, AppColors.danger),
      AlertKind.levelTouch => (Icons.show_chart, AppColors.primaryLight),
      AlertKind.journalReminder => (Icons.edit_note, AppColors.success),
      AlertKind.unscheduled => (Icons.notifications_off_outlined, AppColors.muted),
    };
    final stamp = DateFormat('EEE d MMM · HH:mm').format(event.at.toLocal());
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stamp,
                      style: tabular.copyWith(
                        color: AppColors.faint,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  event.body,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${l10n.alertsWhy}: ${event.reason}',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 10.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (!event.delivered) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      l10n.alertsNotShown,
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The account-screen tile: how many alerts this phone holds, and the way into
/// the list. It loads its own count so the account screen does not have to.
class AlertsSummary extends StatefulWidget {
  const AlertsSummary({super.key});

  @override
  State<AlertsSummary> createState() => _AlertsSummaryState();
}

class _AlertsSummaryState extends State<AlertsSummary> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
    Alerts.instance.revision.addListener(_load);
  }

  @override
  void dispose() {
    Alerts.instance.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final events = await Alerts.instance.history();
    if (!mounted) return;
    setState(() => _count = events.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
        );
        await _load();
      },
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.notifications_outlined, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.alertsHistory,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    l10n.alertsHistoryBody,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            if (_count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_count',
                  style: tabular.copyWith(
                    color: AppColors.primaryLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}
