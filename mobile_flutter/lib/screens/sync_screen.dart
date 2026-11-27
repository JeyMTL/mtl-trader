import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'package:mtl_trader_mobile/core/friendly_error.dart';

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

class _SyncScreenState extends State<SyncScreen> with WidgetsBindingObserver {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  final TextEditingController _broker = TextEditingController();
  final TextEditingController _server = TextEditingController();
  final TextEditingController _login = TextEditingController();
  final TextEditingController _password = TextEditingController();

  Map<String, dynamic> _connection = const {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Timer? _poll;
  DateTime? _pendingSince;
  bool _stalled = false;

  /// The MT5 broker directory, fetched once. Tapping Broker then opens the
  /// whole list with no further network wait.
  List<Mt5Broker> _brokers = const [];
  bool _brokersLoading = true;

  @override
  void initState() {
    super.initState();
    // The two-minute cutoff below stops polling on purpose, so a screen left open
    // while the app was backgrounded would otherwise sit on whatever it last
    // heard. A session that came up meanwhile is invisible until the customer
    // happens to pull to refresh.
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadBrokers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    // Coming back is a fresh attempt, not a continuation of the old one: clear
    // the stall so a slow connect gets its full two minutes again.
    _poll?.cancel();
    setState(() {
      _pendingSince = null;
      _stalled = false;
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _broker.dispose();
    _server.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _status =>
      (asString(_connection['status']) ?? 'none').toLowerCase();
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
      // A rejected attempt keeps its broker and server, so put them back in the
      // form: a retry should correct one field, not retype four. The account
      // number is masked by the API and cannot be prefilled.
      final savedBroker = asString(data['broker']);
      final savedServer = asString(data['server']);
      if (_broker.text.isEmpty && savedBroker != null) {
        _broker.text = savedBroker;
      }
      if (_server.text.isEmpty && savedServer != null) {
        _server.text = savedServer;
      }
      _schedulePoll();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(error);
      });
    }
  }

  /// While a session is being established, refresh so the customer sees it go
  /// live without pulling to refresh. Stops once it settles — and after two
  /// minutes, because a row that never leaves `pending` is a stuck session, not
  /// a slow one, and polling forever hides the problem instead of naming it.
  /// This mirrors the two-minute cutoff on the web connect card.
  void _schedulePoll() {
    _poll?.cancel();
    if (_status != 'pending' && _status != 'connecting') {
      _pendingSince = null;
      if (_stalled) setState(() => _stalled = false);
      return;
    }
    _pendingSince ??= DateTime.now();
    if (DateTime.now().difference(_pendingSince!) >
        const Duration(minutes: 2)) {
      if (!_stalled) setState(() => _stalled = true);
      return;
    }
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
      // A new attempt gets its own two minutes; an old stall must not carry over.
      _pendingSince = null;
      setState(() {
        _connection = data;
        _stalled = false;
      });
      _schedulePoll();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.syncSubmitting)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(_l10n.syncDisconnectTitle,
            style: const TextStyle(fontSize: 16)),
        content: Text(
          _l10n.syncDisconnectBody,
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_l10n.syncDisconnectAction),
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
      setState(() => _error = friendlyError(error));
    }
  }

  String _since(String? iso) {
    final l10n = _l10n;
    if (iso == null || iso.isEmpty) return l10n.syncNotYet;
    final elapsed = DateTime.now().difference(DateTime.parse(iso).toLocal());
    if (elapsed.inSeconds < 60) return l10n.syncSecondsAgo(elapsed.inSeconds);
    if (elapsed.inMinutes < 60) return l10n.syncMinutesAgo(elapsed.inMinutes);
    if (elapsed.inHours < 24) return l10n.syncHoursAgo(elapsed.inHours);
    return l10n.syncDaysAgo(elapsed.inDays);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_l10n.syncTitle),
        actions: [
          IconButton(
            tooltip: _l10n.refresh,
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

  /// The sentence under the status pill.
  ///
  /// A recorded error is the only thing that actually explains a stall, so it
  /// leads. The credential hint used to appear even when the failure was on the
  /// sync host (a terminal that never started), which sent the trader to check a
  /// password that was never the problem.
  String _hint() {
    final l10n = _l10n;
    if (_status == 'connected') {
      return l10n.syncHintConnected;
    }
    final error = asString(_connection['lastError']);
    if (_stalled) {
      if (error != null && error.isNotEmpty) {
        return l10n.syncHintStalledError(error);
      }
      // `connecting` means a slot has taken the account and is signing in, so
      // telling the trader nothing has been attempted (and to disconnect, which
      // wipes the password and restarts the whole year read) is both wrong and
      // actively harmful. A first sync of a cold terminal is measured in
      // minutes, not seconds.
      if (_status == 'connecting') {
        return l10n.syncHintStalledConnecting;
      }
      return l10n.syncHintStalled;
    }
    if (_status == 'connecting') {
      return l10n.syncHintConnecting;
    }
    return l10n.syncHintPending;
  }

  /// Opens the mail app with this connection's details already in the body, so a
  /// "it won't connect" report arrives with the broker, server, account and the
  /// host's own error instead of a screenshot of a spinner.
  Future<void> _contactSupport() async {
    final error = asString(_connection['lastError']);
    final lines = [
      'Broker: ${asString(_connection['broker']) ?? '(unknown)'}',
      'Server: ${asString(_connection['server']) ?? '(unknown)'}',
      'Account: ${asString(_connection['account']) ?? '(unknown)'}',
      'Status: $_status',
      if (error != null && error.isNotEmpty) 'Error: $error',
      '',
      'What happened:',
      '',
    ];
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@mtlledger.com',
      queryParameters: {
        'subject': 'MTL Ledger connection problem',
        'body': lines.join('\n'),
      },
    );
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      // Falls through to the message below.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_l10n.syncMailFailed)),
    );
  }

  Widget _statusCard() {
    final label = switch (_status) {
      'connected' => _l10n.syncStatusConnected,
      'pending' || 'connecting' => _l10n.syncStatusConnecting,
      'failed' => _l10n.syncStatusFailed,
      _ => _l10n.syncStatusDisconnected,
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
                      _l10n.syncCurrent,
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
                label: _l10n.syncBroker,
                value: asString(_connection['broker']) ?? '—',
              ),
              LabelValue(
                label: _l10n.syncServer,
                value: asString(_connection['server']) ?? '—',
              ),
              LabelValue(
                label: _l10n.syncAccount,
                value: asString(_connection['account']) ?? '—',
              ),
              LabelValue(
                label: _l10n.syncLastTrade,
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
          _hint(),
          style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
        ),
        // A connection that failed or has gone quiet is the moment to offer a way
        // out. The mail is prefilled, so support gets the server and the error
        // rather than "it doesn't work".
        if (_status == 'failed' || _stalled) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _contactSupport,
            icon: const Icon(Icons.mail_outline, size: 16),
            label: Text(_l10n.syncContactSupport),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off, size: 16),
          label: Text(_l10n.syncDisconnectLong),
        ),
      ],
    );
  }

  Future<void> _loadBrokers() async {
    try {
      final brokers = await widget.api.brokers();
      if (!mounted) return;
      setState(() {
        _brokers = brokers;
        _brokersLoading = false;
      });
    } catch (_) {
      // The directory is a shortcut, not a requirement: the picker still lets
      // the customer type any broker, and the API accepts it.
      if (!mounted) return;
      setState(() => _brokersLoading = false);
    }
  }

  Future<void> _pickBroker() async {
    if (_brokers.isEmpty && !_brokersLoading) {
      setState(() => _brokersLoading = true);
      await _loadBrokers();
      if (!mounted) return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BrokerSheet(
        brokers: _brokers,
        loading: _brokersLoading,
        selected: _broker.text.trim(),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _broker.text = picked);
  }

  /// Servers we know for the chosen broker, offered as one-tap chips. Typing a
  /// server stays possible, because brokers change theirs faster than any list.
  List<String> _serversFor(String broker) {
    final target = broker.trim().toLowerCase();
    if (target.isEmpty) return const [];
    for (final entry in _brokers) {
      if (entry.name.toLowerCase() == target) return entry.servers;
    }
    return const [];
  }

  Widget _brokerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_l10n.syncBroker,
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: _broker,
          readOnly: true,
          onTap: _pickBroker,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: _l10n.syncSearchBrokers,
            suffixIcon: Icon(Icons.search, size: 16, color: AppColors.faint),
          ),
        ),
      ],
    );
  }

  /// Demo and live servers, labelled and separated. One undifferentiated row
  /// put the demo server behind a dozen live ones, which is the wrong order for
  /// someone testing the app.
  Widget _serverSuggestions() {
    final servers = _serversFor(_broker.text);
    if (servers.isEmpty) return const SizedBox.shrink();

    final demo = servers.where(_isDemoServer).toList();
    final live = servers.where((server) => !_isDemoServer(server)).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (demo.isNotEmpty) _serverRow(_l10n.syncDemo, demo),
          if (demo.isNotEmpty && live.isNotEmpty) const SizedBox(height: 5),
          if (live.isNotEmpty) _serverRow(_l10n.syncLive, live),
        ],
      ),
    );
  }

  static bool _isDemoServer(String server) =>
      RegExp('demo|trial|practice|test', caseSensitive: false).hasMatch(server);

  Widget _serverRow(String label, List<String> servers) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.faint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: servers
                .take(4)
                .map(
                  (server) => InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _server.text = server),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                        color: AppColors.surfaceAlt,
                      ),
                      child: Text(
                        server,
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  /// What the last attempt tried. Shown while the form is visible, so a failed
  /// connection does not look like the app forgot the details — the exact server
  /// string stays on screen to compare against MT5.
  Widget _lastAttempt() {
    final broker = asString(_connection['broker']) ?? '—';
    final server = asString(_connection['server']) ?? '—';
    final account = asString(_connection['account']);
    return Text(
      _l10n.syncLastAttempt(
        '$broker · $server'
        '${account == null || account.isEmpty ? '' : ' · $account'}',
      ),
      style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
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
                _l10n.syncConnectTitle,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _l10n.syncConnectBody,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              if (asString(_connection['server']) case final server?
                  when server.isNotEmpty) ...[
                const SizedBox(height: 10),
                _lastAttempt(),
              ],
              const SizedBox(height: 14),
              _brokerField(),
              const SizedBox(height: 10),
              _field(_server, _l10n.syncServer, 'e.g., ICMarketsSC-Live12'),
              _serverSuggestions(),
              const SizedBox(height: 10),
              _field(
                _login,
                _l10n.syncAccountNumber,
                'e.g., 12345678',
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _field(
                _password,
                _l10n.syncInvestorPassword,
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
                  _l10n.syncInvestorNote,
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
              : Text(_l10n.syncConnectAction),
        ),
        const SizedBox(height: 8),
        Text(
          _l10n.syncAfterConnect,
          style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
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

/// The MT5 directory behind the Broker field.
///
/// Returns the broker the customer picked, or the text they typed when their
/// broker is not listed — `/api/broker/connection` accepts any MT5 broker, so
/// this list is a shortcut rather than a gate.
class _BrokerSheet extends StatefulWidget {
  const _BrokerSheet({
    required this.brokers,
    required this.loading,
    this.selected,
  });

  final List<Mt5Broker> brokers;
  final bool loading;
  final String? selected;

  @override
  State<_BrokerSheet> createState() => _BrokerSheetState();
}

class _BrokerSheetState extends State<_BrokerSheet> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  late final TextEditingController _search = TextEditingController(
    text: widget.selected ?? '',
  );
  late String _query = widget.selected ?? '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Case- and punctuation-insensitive, matching the web picker, so
  /// "ICMarketsSC" finds IC Markets here too.
  static String _norm(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  List<Mt5Broker> get _matches {
    final terms =
        _norm(_query).split(' ').where((term) => term.isNotEmpty).toList();
    if (terms.isEmpty) return widget.brokers;
    return widget.brokers.where((broker) {
      final name = _norm(broker.name);
      final servers = broker.servers.map(_norm).join(' ');
      return terms.every(
        (term) => name.contains(term) || servers.contains(term),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final typed = _query.trim();

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                controller: _search,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: _l10n.syncSearchBrokers,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.faint,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.faint,
                          ),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: widget.loading && widget.brokers.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      children: [
                        if (typed.isNotEmpty)
                          _BrokerTile(
                            name: typed,
                            detail: _l10n.syncUseTyped,
                            onTap: () => Navigator.pop(context, typed),
                          ),
                        if (matches.isEmpty && typed.isEmpty)
                          EmptyState(
                            title: _l10n.syncBrokersUnavailableTitle,
                            body: _l10n.syncBrokersUnavailableBody,
                            icon: Icons.search_off,
                          )
                        else
                          ...matches.map(
                            (broker) => _BrokerTile(
                              name: broker.name,
                              detail: broker.servers.isEmpty
                                  ? _l10n.syncTypeServer
                                  : broker.servers.first,
                              selected: broker.name == widget.selected,
                              onTap: () => Navigator.pop(context, broker.name),
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Text(
                _l10n.syncBrokerCount(widget.brokers.length),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.faint, fontSize: 9.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrokerTile extends StatelessWidget {
  const _BrokerTile({
    required this.name,
    required this.detail,
    required this.onTap,
    this.selected = false,
  });

  final String name;
  final String detail;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            _BrokerMark(name: name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 15, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// The square monogram beside a broker in the picker.
///
/// Real broker logos are third-party trademarks and would have to be licensed
/// and updated; a monogram derived from the name gives every broker a stable,
/// distinct mark with no assets at all. Mirrors `src/lib/broker-mark.ts` so the
/// same broker looks the same on the phone and on the web.
class _BrokerMark extends StatelessWidget {
  const _BrokerMark({required this.name});

  final String name;

  static const double _size = 26;

  static const List<Color> _palette = [
    Color(0xFF3B82F6),
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF22C55E),
    Color(0xFFD5A44E),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFFA855F7),
    Color(0xFF64748B),
  ];

  static String initials(String value) {
    // Punctuation is removed rather than spaced, so a domain suffix does not
    // become a second word: XS.com is XS, not XC.
    final words = value
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), '')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final word = words.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  static Color color(String value) {
    var hash = 0;
    for (var index = 0; index < value.length; index++) {
      hash = (hash * 31 + value.codeUnitAt(index)) & 0xFFFFFFFF;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color(name),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: _size * 0.42,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
