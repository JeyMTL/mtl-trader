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
  DateTime? _pendingSince;
  bool _stalled = false;

  /// The MT5 broker directory, fetched once. Tapping Broker then opens the
  /// whole list with no further network wait.
  List<Mt5Broker> _brokers = const [];
  bool _brokersLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBrokers();
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
        _error = error.toString().replaceFirst('Exception: ', '');
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
    if (DateTime.now().difference(_pendingSince!) > const Duration(minutes: 2)) {
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
              : _stalled
                  ? 'Still not connected after two minutes. That normally means the account number, server or investor password was rejected. Disconnect below and enter the details again.'
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
        Text('Broker', style: TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: _broker,
          readOnly: true,
          onTap: _pickBroker,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search MT5 brokers',
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
          if (demo.isNotEmpty) _serverRow('DEMO', demo),
          if (demo.isNotEmpty && live.isNotEmpty) const SizedBox(height: 5),
          if (live.isNotEmpty) _serverRow('LIVE', live),
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
      'Last attempt: $broker · $server'
      '${account == null || account.isEmpty ? '' : ' · $account'}',
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
              if (asString(_connection['server']) case final server?
                  when server.isNotEmpty) ...[
                const SizedBox(height: 10),
                _lastAttempt(),
              ],
              const SizedBox(height: 14),
              _brokerField(),
              const SizedBox(height: 10),
              _field(_server, 'Server', 'e.g., ICMarketsSC-Live12'),
              _serverSuggestions(),
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
    final terms = _norm(_query)
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList();
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
                  hintText: 'Search MT5 brokers',
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
                            detail: 'Use what you typed',
                            onTap: () => Navigator.pop(context, typed),
                          ),
                        if (matches.isEmpty && typed.isEmpty)
                          const EmptyState(
                            title: 'Broker list unavailable',
                            body:
                                'Type the broker name in the field and it will be used as is.',
                            icon: Icons.search_off,
                          )
                        else
                          ...matches.map(
                            (broker) => _BrokerTile(
                              name: broker.name,
                              detail: broker.servers.isEmpty
                                  ? 'Type the server name'
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
                '${widget.brokers.length} MT5 brokers · any broker works, even one not listed',
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
