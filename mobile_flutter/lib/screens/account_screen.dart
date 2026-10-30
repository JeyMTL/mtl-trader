import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'subscription_screen.dart';

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
  const AccountScreen({super.key, required this.api, this.onProfileChanged});

  final JournalApi api;

  /// Lets the shell rebuild the desk, journal and edge tabs after a setting
  /// that changes their data (currently the report timezone).
  final VoidCallback? onProfileChanged;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.profile();
  }

  Future<void> _refresh() async {
    final next = widget.api.profile();
    setState(() => _future = next);
    try {
      await next;
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

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your journal stays on the server. Sign back in any time.',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
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
        title: const Text(
          'Timezone for the hour report',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                    ),
                  ),
                  trailing: zone == current
                      ? const Icon(
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
            child: const Text('Cancel'),
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
        SnackBar(content: Text('Hour report now uses $selected.')),
      );
      widget.onProfileChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the timezone: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20, color: AppColors.muted),
          ),
        ],
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
              'Signed in';
          final name = asString(profile['full_name']);
          final tier =
              (asString(profile['subscription_tier']) ?? 'free').toLowerCase();
          final status = (asString(profile['subscription_status']) ?? 'trial')
              .toLowerCase();
          final maxTrades = asInt(profile['max_trades']);
          final timezone = asString(profile['timezone']) ?? 'UTC';
          final trialEnds = asDate(profile['trial_ends_at']);
          final periodEnds = asDate(profile['current_period_end']);

          final plan = status == 'active'
              ? (tier == 'pro'
                  ? 'Pro'
                  : tier == 'basic'
                      ? 'Basic'
                      : 'Paid')
              : status == 'trial'
                  ? 'Free trial'
                  : 'Free';

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
                        const Text(
                          'Could not load your subscription',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          snapshot.error.toString(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
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
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FlatCard(
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(24),
                          border: Border.all(
                            color: AppColors.primary.withAlpha(80),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _initials(name, email),
                          style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
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
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.faint,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        text: plan.toUpperCase(),
                        tone: status == 'active'
                            ? Tone.positive
                            : status == 'trial'
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
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 14, 14, 2),
                        child: SectionTitle(title: 'Subscription'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            LabelValue(label: 'Plan', value: plan),
                            const ListDivider(),
                            LabelValue(
                              label: 'Status',
                              value: status == 'active'
                                  ? 'Active'
                                  : status == 'trial'
                                      ? 'Trial'
                                      : status == 'cancelled'
                                          ? 'Cancelled'
                                          : 'Expired',
                              valueColor:
                                  status == 'active' || status == 'trial'
                                      ? AppColors.success
                                      : AppColors.danger,
                            ),
                            const ListDivider(),
                            LabelValue(
                              label: 'Trade limit / month',
                              value:
                                  maxTrades <= 0 ? 'Unlimited' : '$maxTrades',
                            ),
                            const ListDivider(),
                            LabelValue(
                              label: 'Timezone',
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
                                child: const Text('Change'),
                              ),
                            ),
                            if (status == 'trial' && trialEnds != null) ...[
                              const ListDivider(),
                              LabelValue(
                                label: 'Trial ends',
                                value:
                                    DateFormat('d MMM yyyy').format(trialEnds),
                              ),
                            ],
                            if (status == 'active' && periodEnds != null) ...[
                              const ListDivider(),
                              LabelValue(
                                label: 'Paid through',
                                value:
                                    DateFormat('d MMM yyyy').format(periodEnds),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openPlans,
                  icon: const Icon(Icons.credit_card, size: 16),
                  label: const Text('View plans & billing'),
                ),
                const SizedBox(height: 10),
                const FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRIVATE MEDIA',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Journal photos and voice notes live in a private bucket. '
                        'Each file is signed for one hour and only your account can request it.',
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
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  child: const Text('Sign out'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'MTL Trader · flat mobile journal\nTrades, notes and media stay on your Supabase project.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 9.5,
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
