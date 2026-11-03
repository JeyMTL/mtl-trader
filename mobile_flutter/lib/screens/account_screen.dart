import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/features.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/language_picker.dart';
import '../ui/perf_overlay.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'subscription_screen.dart';
import 'sync_screen.dart';

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
      path: 'jfx064@gmail.com',
      queryParameters: {
        'subject': 'MTL Trader support',
        'body': 'Account: $account\n\nWhat happened:\n',
      },
    );
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      // Falls through to the address below.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No mail app found. Write to jfx064@gmail.com'),
      ),
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
      const SnackBar(content: Text('Could not open the store listing.')),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
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
        title: const Text(
          'Profile picture',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a link to an image. Leave it empty to use the picture tied to your email, or your initials when there is none.',
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
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
                ? 'Profile picture cleared.'
                : 'Profile picture updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the picture: $error')),
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
            icon: Icon(Icons.refresh, size: 20, color: AppColors.muted),
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
                        Text(
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
                if (kMt5SyncEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openSync,
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Connect MT5 account'),
                  ),
                ],
                const SizedBox(height: 10),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(
                        title: 'Help & feedback',
                        subtitle:
                            'Questions, bugs, or something the journal should do. Every message is read.',
                      ),
                      const SizedBox(height: 10),
                      LabelValue(
                        label: 'Email support',
                        value: 'jfx064@gmail.com',
                        trailing: TextButton(
                          onPressed: _emailSupport,
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Write'),
                        ),
                      ),
                      const ListDivider(),
                      LabelValue(
                        label: 'Rate MTL Trader',
                        value: 'One tap in the store',
                        trailing: TextButton(
                          onPressed: _rateApp,
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Rate'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(
                        title: 'Appearance',
                        subtitle:
                            'Dark, light, or follow the device setting. Saved on this phone.',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final mode in ThemeMode.values) ...[
                            _ThemeChoice(mode: mode),
                            if (mode != ThemeMode.values.last)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(
                        title: 'Diagnostics',
                        subtitle:
                            'Frame times, measured on this phone. Turn it on, pan the chart, read the worst frame.',
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: FrameOverlaySettings.visible,
                        builder: (context, visible, _) => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: visible,
                          onChanged: FrameOverlaySettings.set,
                          title: Text(
                            'Frame time overlay',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const LanguagePicker(),
                const SizedBox(height: 10),
                FlatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRIVATE MEDIA',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: kMinLabelSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
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
                    side: BorderSide(color: AppColors.danger),
                  ),
                  child: const Text('Sign out'),
                ),
                const SizedBox(height: 14),
                Text(
                  'MTL Trader · flat mobile journal\nTrades, notes and media stay on your Supabase project.',
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

/// One of the three appearance options. The root rebuilds the tree when the
/// mode changes, so this needs no local state.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final active = ThemeController.instance.mode == mode;
    final label = switch (mode) {
      ThemeMode.dark => 'Dark',
      ThemeMode.light => 'Light',
      ThemeMode.system => 'System',
    };
    final icon = switch (mode) {
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };

    return Expanded(
      child: InkWell(
        onTap: () => ThemeController.instance.setMode(mode),
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
