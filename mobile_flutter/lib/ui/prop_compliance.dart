import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/prop_rules.dart';
import '../services/journal_api.dart';
import 'shimmer.dart';
import 'theme.dart';
import 'widgets.dart';

/// Prop-firm rule monitor.
///
/// Leads with headroom rather than P&L: a prop evaluation is lost by breaking a
/// rule, so the useful number is how much of today's loss budget is left and how
/// far the trailing drawdown can still fall. Everything shown comes from the
/// server's `prop_status()`, so the device never decides whether a rule broke.
class PropComplianceCard extends StatefulWidget {
  const PropComplianceCard({super.key, required this.api});

  final JournalApi api;

  @override
  State<PropComplianceCard> createState() => _PropComplianceCardState();
}

class _PropComplianceCardState extends State<PropComplianceCard> {
  late Future<_PropData> _future;
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PropData> _load() async {
    final body = await widget.api.propRules();
    return _PropData.fromMap(body);
  }

  Future<void> _save(PropRules rules) async {
    final problem = rules.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = await widget.api.savePropRules(rules);
      if (!mounted) return;
      setState(() {
        _future = Future<_PropData>.value(_PropData.fromMap(body));
        _editing = false;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PropData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FlatCard(
            child: Text(
              snapshot.error.toString().replaceFirst('Exception: ', ''),
              style: TextStyle(color: AppColors.faint, fontSize: 11.5),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const FlatCard(child: SkeletonCard(height: 96));
        }
        if (data.missing) {
          return FlatCard(
            borderColor: AppColors.danger.withAlpha(70),
            child: Text(
              'Prop-rule monitoring needs the database migration '
              '20261111_prop_rules.sql. Apply it and refresh.',
              style: TextStyle(
                  color: AppColors.danger, fontSize: 11.5, height: 1.45),
            ),
          );
        }

        final status = data.status;
        final level = status?.level ?? PropLevel.ok;
        final accent = switch (level) {
          PropLevel.breach => AppColors.danger,
          PropLevel.warning => AppColors.primary,
          PropLevel.ok => AppColors.success,
        };

        if (_editing) {
          return _RulesForm(
            initial: data.rules ?? PropRules.defaults(),
            saving: _saving,
            error: _error,
            onCancel:
                status == null ? null : () => setState(() => _editing = false),
            onSave: _save,
          );
        }

        return FlatCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Prop rule monitor',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Flexible rather than a fixed pill: at the largest system
                  // text size the label wraps beside the title instead of
                  // pushing the row past the card's edge.
                  if (status != null)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(30),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          switch (level) {
                            PropLevel.breach => 'Rule breached',
                            PropLevel.warning => 'Close to a limit',
                            PropLevel.ok => 'Within rules',
                          },
                          style: TextStyle(
                            color: accent,
                            fontSize: kMinLabelSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                status == null
                    ? 'Track a prop-firm evaluation: daily loss, trailing drawdown and the profit target.'
                    : 'Headroom against the evaluation rules you set.',
                style: TextStyle(
                    color: AppColors.faint, fontSize: 11.5, height: 1.45),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: AppColors.danger, fontSize: 11.5)),
              ],
              if (status == null) ...[
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => setState(() => _editing = true),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Set up rules'),
                ),
              ] else ...[
                const SizedBox(height: 12),
                if (level != PropLevel.ok) ...[
                  Text(
                    status.status == 'breach_daily'
                        ? 'Today’s loss has reached the daily limit — most firms require you to stop for the day.'
                        : status.status == 'breach_drawdown'
                            ? 'The drawdown limit has been reached. Check the firm’s rules before opening another trade.'
                            : status.status == 'breach_consistency'
                                ? 'One day is carrying more than the consistency limit allows. The evaluation can be refused even after hitting the target — spread the gain across more days.'
                                : 'You are within 20% of a rule limit. Position size and stop distance matter more than the next setup.',
                    style:
                        TextStyle(color: accent, fontSize: 11.5, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                ],
                _Meter(
                  label: 'Daily loss',
                  used: status.dailyPnl < 0 ? -status.dailyPnl : 0,
                  limit: status.dailyLossLimit,
                  detail:
                      '${money(status.dailyHeadroom)} left today · limit ${percent(status.maxDailyLossPct)}',
                  tone: status.status == 'breach_daily'
                      ? AppColors.danger
                      : status.status == 'warn_daily'
                          ? AppColors.primary
                          : AppColors.success,
                ),
                const SizedBox(height: 8),
                _Meter(
                  label: status.trailingDrawdown
                      ? 'Trailing drawdown'
                      : 'Drawdown',
                  used: status.drawdown,
                  limit: status.drawdownLimit,
                  detail:
                      '${money(status.drawdownHeadroom)} left · peak ${money(status.peakEquity)}',
                  tone: status.status == 'breach_drawdown'
                      ? AppColors.danger
                      : status.status == 'warn_drawdown'
                          ? AppColors.primary
                          : AppColors.success,
                ),
                const SizedBox(height: 8),
                _Meter(
                  label: 'Profit target',
                  used: status.profitProgress < 0 ? 0 : status.profitProgress,
                  limit: status.profitTarget,
                  detail:
                      '${status.tradingDays}/${status.minTradingDays} qualifying days',
                  tone: AppColors.primary,
                ),
                if (status.consistencyPct > 0) ...[
                  const SizedBox(height: 8),
                  _Meter(
                    label: 'Consistency',
                    used: status.consistency,
                    limit: status.consistencyPct,
                    percentUnits: true,
                    detail:
                        'Best day ${money(status.bestDayPnl)} · maximum '
                        '${percent(status.consistencyPct)} of total profit',
                    tone: status.status == 'breach_consistency'
                        ? AppColors.danger
                        : status.status == 'warn_consistency'
                            ? AppColors.primary
                            : AppColors.success,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Evaluated from ${money(status.accountSize)} of starting balance. '
                        'A firm’s own dashboard wins any disagreement.',
                        style: TextStyle(
                            color: AppColors.faint,
                            fontSize: kMinLabelSize,
                            height: 1.4),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _editing = true),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PropData {
  const _PropData({
    required this.configured,
    required this.missing,
    this.rules,
    this.status,
  });

  final bool configured;
  final bool missing;
  final PropRules? rules;
  final PropStatus? status;

  factory _PropData.fromMap(Map<String, dynamic> body) {
    final missing = body['missing'] == true;
    final configured = body['configured'] == true;
    final rules = body['rules'];
    final status = body['status'];
    return _PropData(
      configured: configured,
      missing: missing,
      rules: rules is Map
          ? PropRules.fromMap(Map<String, dynamic>.from(rules))
          : null,
      status: configured && status is Map && status['configured'] != false
          ? PropStatus.fromMap(Map<String, dynamic>.from(status))
          : null,
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.used,
    required this.limit,
    required this.detail,
    required this.tone,
    this.percentUnits = false,
  });

  final String label;
  final double used;
  final double limit;
  final String detail;
  final Color tone;

  /// The consistency meter measures percentages, not currency.
  final bool percentUnits;

  String _format(double value) =>
      percentUnits ? percent(value) : money(value);

  @override
  Widget build(BuildContext context) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: kMinLabelSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: Text(
                '${_format(used)} / ${_format(limit)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: kMinLabelSize,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(tone),
          ),
        ),
        const SizedBox(height: 3),
        Text(detail,
            style: TextStyle(color: AppColors.faint, fontSize: kMinLabelSize)),
      ],
    );
  }
}

class _RulesForm extends StatefulWidget {
  const _RulesForm({
    required this.initial,
    required this.saving,
    required this.error,
    required this.onSave,
    this.onCancel,
  });

  final PropRules initial;
  final bool saving;
  final String? error;
  final ValueChanged<PropRules> onSave;
  final VoidCallback? onCancel;

  @override
  State<_RulesForm> createState() => _RulesFormState();
}

class _RulesFormState extends State<_RulesForm> {
  late PropRules _rules;
  late final TextEditingController _account;
  late final TextEditingController _daily;
  late final TextEditingController _drawdown;
  late final TextEditingController _target;
  late final TextEditingController _days;
  late final TextEditingController _consistency;

  @override
  void initState() {
    super.initState();
    // `widget` is not available to field initialisers, so the controllers are
    // built here rather than inline.
    final initial = widget.initial;
    _rules = initial;
    _account = TextEditingController(text: _trim(initial.accountSize));
    _daily = TextEditingController(text: _trim(initial.maxDailyLossPct));
    _drawdown = TextEditingController(text: _trim(initial.maxDrawdownPct));
    _target = TextEditingController(text: _trim(initial.profitTargetPct));
    _days = TextEditingController(text: '${initial.minTradingDays}');
    _consistency =
        TextEditingController(text: _trim(initial.consistencyPct));
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  @override
  void dispose() {
    _account.dispose();
    _daily.dispose();
    _drawdown.dispose();
    _target.dispose();
    _days.dispose();
    _consistency.dispose();
    super.dispose();
  }

  void _sync() {
    _rules = _rules.copyWith(
      accountSize: double.tryParse(_account.text) ?? _rules.accountSize,
      maxDailyLossPct: double.tryParse(_daily.text) ?? _rules.maxDailyLossPct,
      maxDrawdownPct: double.tryParse(_drawdown.text) ?? _rules.maxDrawdownPct,
      profitTargetPct: double.tryParse(_target.text) ?? _rules.profitTargetPct,
      minTradingDays: int.tryParse(_days.text) ?? _rules.minTradingDays,
      consistencyPct:
          double.tryParse(_consistency.text) ?? _rules.consistencyPct,
    );
  }

  Future<void> _pickDate() async {
    final parsed = DateTime.tryParse(_rules.startedOn) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _rules = _rules.copyWith(
        startedOn: '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Evaluation rules',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _number('Account size', _account, 'USD'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _number('Max daily loss', _daily, '%')),
              const SizedBox(width: 8),
              Expanded(child: _number('Max drawdown', _drawdown, '%')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _number('Profit target', _target, '%')),
              const SizedBox(width: 8),
              Expanded(child: _number('Min trading days', _days, 'days')),
            ],
          ),
          const SizedBox(height: 8),
          _number('Consistency limit', _consistency, '%'),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No single day may make more than this share of the total gain. '
              'Most firms publish 20–40%.',
              style: TextStyle(
                color: AppColors.faint,
                fontSize: kMinLabelSize,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Trailing drawdown',
              style: TextStyle(color: AppColors.text, fontSize: 12.5),
            ),
            subtitle: Text(
              'Measured from the peak balance, as most firms do.',
              style: TextStyle(color: AppColors.faint, fontSize: kMinLabelSize),
            ),
            value: _rules.trailingDrawdown,
            onChanged: (value) => setState(
                () => _rules = _rules.copyWith(trailingDrawdown: value)),
          ),
          InkWell(
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Evaluation started',
                      style: TextStyle(color: AppColors.faint, fontSize: 11.5),
                    ),
                  ),
                  Text(
                    _rules.startedOn,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.edit_calendar_outlined,
                      size: 15, color: AppColors.muted),
                ],
              ),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 4),
            Text(widget.error!,
                style: TextStyle(color: AppColors.danger, fontSize: 11.5)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: widget.saving
                    ? null
                    : () {
                        _sync();
                        widget.onSave(_rules);
                      },
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(widget.saving ? 'Saving…' : 'Save rules'),
              ),
              if (widget.onCancel != null) ...[
                const SizedBox(width: 8),
                TextButton(
                    onPressed: widget.onCancel, child: const Text('Cancel')),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _number(
      String label, TextEditingController controller, String suffix) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: AppColors.text, fontSize: 12.5),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        suffixText: suffix,
        labelStyle: TextStyle(color: AppColors.faint, fontSize: 11.5),
        suffixStyle: TextStyle(color: AppColors.faint, fontSize: 11),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
