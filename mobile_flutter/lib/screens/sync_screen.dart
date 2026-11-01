import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// MT5 connection, for customers whose only device is a phone.
///
/// A phone cannot run an Expert Advisor, so the account is connected by handing
/// over the broker's **investor** (read-only) password, which the service uses on
/// its own host. The card never sees the password again after it is sent, and
/// MT5 lets the customer revoke access at any time by changing it.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.api});

  final JournalApi api;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final TextEditingController _broker = TextEditingController();
  final TextEditingController _server = TextEditingController();
  final TextEditingController _login = TextEditingController();
  final TextEditingController _password = TextEditingController();

  Map<String, dynamic> _connection = const {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _broker.dispose();
    _server.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _status => (asString(_connection['status']) ?? 'none').toLowerCase();
  bool get _active =>
      _status == 'connected' || _status == 'pending' || _status == 'connecting';

  Future<void> _load() async {
    try {
      final data = await widget.api.brokerConnection();
      if (!mounted) return;
      setState(() {
        _connection = data;
        _loading = false;
      });
      _schedulePoll();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// While a session is being established, refresh so the customer sees it go
  /// live without pulling to refresh. Stops once it settles.
  void _schedulePoll() {
    _poll?.cancel();
    if (_status != 'pending' && _status != 'connecting') return;
    _poll = Timer(const Duration(seconds: 6), _load);
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.api.connectBroker(
        broker: _broker.text.trim(),
        server: _server.text.trim(),
        login: _login.text.trim(),
        investorPassword: _password.text,
      );
      if (!mounted) return;
      _password.clear();
      setState(() => _connection = data);
      _schedulePoll();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection saved. We are signing in now.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Disconnect account?', style: TextStyle(fontSize: 16)),
        content: Text(
          'We delete the stored password and stop syncing. Your trades stay in your journal.',
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final data = await widget.api.disconnectBroker();
      if (!mounted) return;
      setState(() => _connection = data);
      _poll?.cancel();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _since(String? iso) {
    if (iso == null || iso.isEmpty) return 'not yet';
    final elapsed = DateTime.now().difference(DateTime.parse(iso).toLocal());
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s ago';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('MT5 Sync'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: Icon(Icons.refresh, size: 20, color: AppColors.muted),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
              children: [
                if (_error != null) ...[
                  FlatCard(
                    borderColor: AppColors.danger.withAlpha(80),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_active) _statusCard() else _form(),
              ],
            ),
    );
  }

  Widget _statusCard() {
    final label = switch (_status) {
      'connected' => 'Connected',
      'pending' || 'connecting' => 'Connecting…',
      'failed' => 'Connection failed',
      _ => 'Disconnected',
    };
    final tone = _status == 'connected'
        ? Tone.positive
        : _status == 'failed'
            ? Tone.negative
            : Tone.neutral;

    return Column(
      children: [
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Current connection',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Pill(text: label.toUpperCase(), tone: tone),
                ],
              ),
              const SizedBox(height: 10),
              LabelValue(
                label: 'Broker',
                value: asString(_connection['broker']) ?? '—',
              ),
              LabelValue(
                label: 'Server',
                value: asString(_connection['server']) ?? '—',
              ),
              LabelValue(
                label: 'Account',
                value: asString(_connection['account']) ?? '—',
              ),
              LabelValue(
                label: 'Last trade',
                value: _since(asString(_connection['lastSyncAt'])),
              ),
              if (asString(_connection['lastError']) case final message?
                  when message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _status == 'connected'
              ? 'Closed trades arrive automatically, even with the app shut.'
              : 'A session usually connects in under a minute. If it does not, disconnect and check the account number, server and investor password.',
          style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off, size: 16),
          label: const Text('Disconnect and delete password'),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect automatically',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No PC needed. Enter the account details once and every closed trade lands in your journal.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              _field(_broker, 'Broker', 'e.g., IC Markets'),
              const SizedBox(height: 10),
              _field(_server, 'Server', 'e.g., ICMarketsSC-Live12'),
              const SizedBox(height: 10),
              _field(
                _login,
                'Account number',
                'e.g., 12345678',
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _field(
                _password,
                'Investor (read-only) password',
                '••••••••',
                obscure: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FlatCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 14, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Use the investor password, never your trading password: '
                  'MT5 → Settings → your account → Change investor password. '
                  'It cannot trade, it is stored encrypted, and changing it in '
                  'MT5 instantly cuts our access.',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.ink,
                  ),
                )
              : const Text('Connect account'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
