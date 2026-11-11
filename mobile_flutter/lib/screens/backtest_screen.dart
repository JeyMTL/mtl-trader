import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/backtest.dart';
import '../core/format.dart';
import '../services/backtest_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'custom_backtest_screen.dart';

/// The API refuses bodies over 4,000,000 characters; refuse the file first so
/// the trader learns it here instead of after an upload.
const int _maxCsvBytes = 4000000;

/// The web desk's backtest workbench, on the phone.
///
/// Same rules, same form, same server: a CSV goes up, `/api/backtest` runs the
/// deterministic engine and archives the run, and the report is rendered here
/// with its metrics, curve, split, assumptions, warnings and trades. Saved runs
/// are listed from the same route and can be reopened or deleted.
class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key, this.api});

  final BacktestApi? api;

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  late final BacktestApi _api = widget.api ?? BacktestApi();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _symbol = TextEditingController(text: 'EURUSD');
  final TextEditingController _timeframe = TextEditingController(text: 'M1');
  final TextEditingController _csv = TextEditingController();
  final TextEditingController _balance = TextEditingController(text: '10000');
  final TextEditingController _risk = TextEditingController(text: '1');
  final TextEditingController _contractSize =
      TextEditingController(text: '100000');
  final TextEditingController _maxLeverage = TextEditingController(text: '30');
  final TextEditingController _spread = TextEditingController(text: '0.0002');
  final TextEditingController _slippage = TextEditingController(text: '0');
  final TextEditingController _commission = TextEditingController(text: '7');
  final TextEditingController _splitRatio = TextEditingController(text: '0.7');
  final TextEditingController _clockOffset = TextEditingController(text: '0');

  /// One field per tunable rule, rebuilt when the strategy changes.
  final Map<String, TextEditingController> _paramControllers = {};

  /// Controllers from a strategy the trader switched away from. They are
  /// disposed with the screen rather than at the switch: the old fields are
  /// still attached during that rebuild.
  final List<TextEditingController> _retired = [];

  String _strategyId = backtestStrategies.first.id;

  /// Rules compiled from a plain-language description. When present they replace
  /// the library strategy: the run is sent as `custom` with this spec.
  CompiledBacktest? _compiled;
  String? _fileName;
  BacktestReport? _report;
  List<SavedBacktestRun> _runs = const [];
  bool _busy = false;
  bool _loadingRuns = true;
  String? _error;
  bool _upgradeRequired = false;

  BacktestStrategy get _strategy =>
      backtestStrategyById(_strategyId) ?? backtestStrategies.first;

  @override
  void initState() {
    super.initState();
    _loadStrategy(_strategyId);
    _loadRuns();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _symbol,
      _timeframe,
      _csv,
      _balance,
      _risk,
      _contractSize,
      _maxLeverage,
      _spread,
      _slippage,
      _commission,
      _splitRatio,
      _clockOffset,
      ..._retired,
      ..._paramControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadStrategy(String id) {
    final definition = backtestStrategyById(id) ?? backtestStrategies.first;
    _retired.addAll(_paramControllers.values);
    _paramControllers.clear();
    for (final spec in definition.params) {
      _paramControllers[spec.key] =
          TextEditingController(text: spec.defaultText);
    }
    _strategyId = definition.id;
  }

  void _chooseStrategy(String id) {
    setState(() {
      _compiled = null;
      _loadStrategy(id);
      _report = null;
    });
  }

  /// Opens the custom workbench. The compiled rules stay on this screen so the
  /// trader can check them beside the costs before pressing Run.
  Future<void> _openCustom() async {
    final compiled = await Navigator.of(context).push<CompiledBacktest>(
      MaterialPageRoute(
        builder: (_) => CustomBacktestScreen(
          api: _api,
          symbol: _symbol.text.trim(),
          timeframe: _timeframe.text.trim().toUpperCase(),
        ),
      ),
    );
    if (compiled == null || !mounted) return;
    setState(() {
      _compiled = compiled;
      _timeframe.text = compiled.timeframe;
      if (_name.text.trim().isEmpty) _name.text = compiled.name;
      _report = null;
      _error = null;
      _upgradeRequired = false;
    });
  }

  Future<void> _loadRuns() async {
    try {
      final runs = await _api.savedRuns();
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _loadingRuns = false;
      });
    } catch (_) {
      // The workbench still runs without the archive.
      if (!mounted) return;
      setState(() => _loadingRuns = false);
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      _fail('Could not read that file. Try picking it again.');
      return;
    }
    if (bytes.length > _maxCsvBytes) {
      _fail('That file is over 4 MB. Export a shorter range.');
      return;
    }

    final text = utf8Text(bytes);
    setState(() {
      _csv.text = text;
      _fileName = file.name;
      _error = null;
      _upgradeRequired = false;
      if (_name.text.trim().isEmpty) {
        final dot = file.name.lastIndexOf('.');
        final base = dot > 0 ? file.name.substring(0, dot) : file.name;
        _name.text = base.length > 60 ? base.substring(0, 60) : base;
      }
    });
  }

  /// UTF-8, with replacement characters rather than an exception for a stray
  /// byte — the server parses the text either way.
  static String utf8Text(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  void _fail(String message, {bool upgrade = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _upgradeRequired = upgrade;
    });
  }

  /// An empty field is `0` (a cleared number is zero on the web too); text that
  /// is not a number is left out, so the server applies its default.
  double? _numeric(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    return double.tryParse(text);
  }

  Map<String, double?> _params() => {
        for (final entry in _paramControllers.entries)
          entry.key: double.tryParse(entry.value.text.trim()),
      };

  Future<void> _run() async {
    if (_csv.text.trim().isEmpty) {
      _fail('Upload or paste the bar data first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _upgradeRequired = false;
    });

    try {
      final result = await _api.run(
        BacktestRequest(
          csv: _csv.text,
          symbol: _symbol.text.trim().toUpperCase(),
          timeframe: _timeframe.text.trim().toUpperCase(),
          strategyId: _compiled == null ? _strategyId : 'custom',
          ruleSpec: _compiled?.spec,
          params: _params(),
          name: _name.text.trim(),
          initialBalance: _numeric(_balance),
          riskPercent: _numeric(_risk),
          contractSize: _numeric(_contractSize),
          maxLeverage: _numeric(_maxLeverage),
          spread: _numeric(_spread),
          slippage: _numeric(_slippage),
          commission: _numeric(_commission),
          splitRatio: _numeric(_splitRatio),
          timezoneOffsetMinutes: _numeric(_clockOffset),
        ),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _report = result.report;
      });
      _toast(
        result.saved
            ? 'Run complete and saved.'
            : 'Run complete — the archive write failed.',
      );
      await _loadRuns();
    } catch (error) {
      if (error is BacktestApiException) {
        _fail(error.message, upgrade: error.upgradeRequired);
      } else {
        _fail('The run could not be completed. Try again.');
      }
    }
  }

  Future<void> _openSaved(SavedBacktestRun run) async {
    setState(() => _busy = true);
    try {
      final report = await _api.savedRun(run.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _report = report;
        _error = null;
      });
    } catch (error) {
      _fail(
        error is BacktestApiException
            ? error.message
            : 'Could not load that run.',
      );
    }
  }

  Future<void> _deleteSaved(SavedBacktestRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this saved run?'),
        content: Text(
          run.name.isEmpty ? 'This run' : run.name,
          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _api.delete(run.id);
      if (!mounted) return;
      setState(() {
        _runs = _runs.where((entry) => entry.id != run.id).toList();
      });
      _toast('Run deleted.');
    } catch (error) {
      _fail(
        error is BacktestApiException
            ? error.message
            : 'Could not delete the run.',
      );
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Backtest')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          Text(
            'Replay a rule-based strategy over your own MT5 bar data, with '
            'costs and the fill assumptions printed on the result.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openCustom,
            icon: const Icon(Icons.auto_fix_high, size: 17),
            label: const Text('Custom backtest'),
          ),
          const SizedBox(height: 14),
          _barsCard(),
          const SizedBox(height: 12),
          _strategyCard(),
          const SizedBox(height: 12),
          _costsCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FlatCard(
              borderColor: (_upgradeRequired ? AppColors.primary : AppColors.danger)
                  .withAlpha(90),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _upgradeRequired
                        ? Icons.workspace_premium_outlined
                        : Icons.error_outline,
                    size: 18,
                    color: _upgradeRequired
                        ? AppColors.primary
                        : AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow, size: 18),
            label: Text(_busy ? 'Simulating…' : 'Run backtest'),
          ),
          const SizedBox(height: 18),
          if (report == null) _emptyCard() else ..._reportCards(report),
          const SizedBox(height: 18),
          _savedCard(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ form

  Widget _cardTitle(String title) => Text(
        title,
        style: TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      );

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          style: TextStyle(color: AppColors.faint, fontSize: 11),
        ),
      );

  Widget _numberField(
    String label,
    TextEditingController controller, {
    bool allowNegative = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(
            decimal: true,
            signed: allowNegative,
          ),
          style: tabular.copyWith(color: AppColors.text, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
        ),
      ],
    );
  }

  /// Pairs of fields, two to a row like the web form.
  Widget _fieldPairs(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(120.0, (constraints.maxWidth - 10) / 2);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final field in fields) SizedBox(width: width, child: field),
          ],
        );
      },
    );
  }

  Widget _barsCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('1. Bar data'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.upload_file, size: 17),
            label: Text(
              _fileName ?? 'Choose a CSV or paste below',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _fileName = null;
                          _csv.clear();
                        }),
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Clear'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _csv,
            minLines: 5,
            maxLines: 8,
            spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
            style: tabular.copyWith(color: AppColors.text, fontSize: 11),
            decoration: const InputDecoration(
              hintText:
                  '<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\n'
                  '2026.10.01\t10:00:00\t1.1050\t1.1060\t1.1040\t1.1055',
              hintMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Up to 60,000 bars. In MT5: select the chart with Ctrl+A, copy, '
            'paste into a text file.',
            style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _strategyCard() {
    final definition = _strategy;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('2. Strategy'),
          const SizedBox(height: 10),
          _fieldLabel('Run name'),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'e.g. EURUSD M1 SMA cross',
            ),
          ),
          const SizedBox(height: 12),
          _fieldPairs([
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('Symbol'),
                TextField(
                  controller: _symbol,
                  textCapitalization: TextCapitalization.characters,
                  style: tabular.copyWith(color: AppColors.text, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  onChanged: (value) {
                    final upper = value.toUpperCase();
                    if (upper == value) return;
                    _symbol.value = TextEditingValue(
                      text: upper,
                      selection: TextSelection.collapsed(offset: upper.length),
                    );
                  },
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('Timeframe'),
                TextField(
                  controller: _timeframe,
                  style: tabular.copyWith(color: AppColors.text, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  onChanged: (value) {
                    final upper = value.toUpperCase();
                    if (upper == value) return;
                    _timeframe.value = TextEditingValue(
                      text: upper,
                      selection: TextSelection.collapsed(offset: upper.length),
                    );
                  },
                ),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          if (_compiled == null) ...[
            _fieldLabel('Rules'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.field),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _strategyId,
                  dropdownColor: AppColors.surfaceAlt,
                  style: TextStyle(color: AppColors.text, fontSize: 13.5),
                  icon: Icon(Icons.expand_more, size: 18, color: AppColors.faint),
                  items: [
                    for (final strategy in backtestStrategies)
                      DropdownMenuItem(
                        value: strategy.id,
                        child: Text(strategy.name),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) _chooseStrategy(value);
                        },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              definition.description,
              style:
                  TextStyle(color: AppColors.faint, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 10),
            _fieldPairs([
              for (final spec in definition.params)
                _numberField(spec.label, _paramControllers[spec.key]!),
            ]),
          ] else ...[
            _fieldLabel('Compiled rules'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.field),
                border: Border.all(color: AppColors.primary.withAlpha(70)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _compiled!.name,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final rule in _compiled!.rules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '· $rule',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() => _compiled = null),
              icon: const Icon(Icons.library_books_outlined, size: 15),
              label: const Text('Use a library strategy instead'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _costsCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('3. Sizing and costs'),
          const SizedBox(height: 10),
          _fieldPairs([
            _numberField('Starting balance', _balance),
            _numberField('Risk per trade %', _risk),
            _numberField('Contract size', _contractSize),
            _numberField('Max leverage', _maxLeverage),
            _numberField('Spread (price)', _spread),
            _numberField('Slippage (price)', _slippage),
            _numberField('Commission / trade', _commission),
            _numberField('In-sample share', _splitRatio),
            _numberField('Server clock offset (min)', _clockOffset,
                allowNegative: true),
          ]),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- results

  Widget _emptyCard() {
    return FlatCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      child: Column(
        children: [
          Icon(Icons.science_outlined, size: 34, color: AppColors.faint),
          const SizedBox(height: 10),
          Text(
            'No run yet',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload a history export, choose the rules and the cost model, and '
            'the report appears here with its assumptions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.faint, fontSize: 11.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  List<Widget> _reportCards(BacktestReport report) {
    return [
      _summaryCard(report),
      if (report.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        _warningsCard(report.warnings),
      ],
      if (report.equity.length > 1) ...[
        const SizedBox(height: 12),
        _equityCard(report.equity),
      ],
      if (report.split != null) ...[
        const SizedBox(height: 12),
        _splitCard(report.split!),
      ],
      if (report.assumptions.isNotEmpty) ...[
        const SizedBox(height: 12),
        _assumptionsCard(report.assumptions),
      ],
      if (report.trades.isNotEmpty) ...[
        const SizedBox(height: 12),
        _tradesCard(report.trades),
      ],
    ];
  }

  Widget _summaryCard(BacktestReport report) {
    final net = report.metrics.netPnl;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${report.symbol} · ${report.strategyName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${NumberFormat.decimalPattern('en_US').format(report.barCount)} '
                      'bars · ${_dayRange(report.from, report.to)} · '
                      '${report.timeframe}',
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (net >= 0 ? AppColors.success : AppColors.danger)
                      .withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _signed(net),
                  style: tabular.copyWith(
                    color: net >= 0 ? AppColors.success : AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _metricsGrid(report.metrics),
        ],
      ),
    );
  }

  Widget _metricsGrid(BacktestMetrics metrics) {
    final items = <({String label, String value, Tone tone})>[
      (
        label: 'Net P&L',
        value: _signed(metrics.netPnl),
        tone: metrics.netPnl >= 0 ? Tone.positive : Tone.negative,
      ),
      (
        label: 'Return',
        value: _pct(metrics.returnPct, 2),
        tone: metrics.returnPct >= 0 ? Tone.positive : Tone.negative,
      ),
      (
        label: 'Profit factor',
        value: _ratio(metrics.profitFactor),
        tone: Tone.neutral,
      ),
      (label: 'Win rate', value: _pct(metrics.winRate), tone: Tone.neutral),
      (label: 'Trades', value: '${metrics.trades}', tone: Tone.neutral),
      (
        label: 'Expectancy',
        value: _signed(metrics.expectancy),
        tone: Tone.neutral,
      ),
      (
        label: 'Max drawdown',
        value: _pct(metrics.maxDrawdownPct, 2),
        tone: Tone.negative,
      ),
      (
        label: 'Sharpe',
        value: metrics.sharpe == null ? '—' : metrics.sharpe!.toStringAsFixed(2),
        tone: Tone.neutral,
      ),
      (
        label: 'Exposure',
        value: _pct(metrics.exposurePct, 0),
        tone: Tone.neutral,
      ),
      (
        label: 'Avg R',
        value: metrics.avgRMultiple == null
            ? '—'
            : metrics.avgRMultiple!.toStringAsFixed(2),
        tone: Tone.neutral,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(120.0, (constraints.maxWidth - 8) / 2);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: MetricCard(
                  label: item.label,
                  value: item.value,
                  tone: item.tone,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _warningsCard(List<String> warnings) {
    const amber = Color(0xFFEAB308);
    return FlatCard(
      borderColor: amber.withAlpha(70),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 15, color: amber),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _equityCard(List<BacktestEquityPoint> points) {
    final values = points.map((point) => point.equity).toList();
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final first = points.first;
    final last = points.last;
    final rising = last.equity >= first.equity;
    final color = rising ? AppColors.success : AppColors.danger;

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Equity'),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _EquityCurvePainter(
                values: values,
                color: color,
                fill: color.withAlpha(36),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _day(first.time),
                style: TextStyle(color: AppColors.faint, fontSize: 10.5),
              ),
              const Spacer(),
              Text(
                '${money(min)} – ${money(max)}',
                style: tabular.copyWith(
                  color: AppColors.faint,
                  fontSize: 10.5,
                ),
              ),
              const Spacer(),
              Text(
                _day(last.time),
                style: TextStyle(color: AppColors.faint, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _splitCard(BacktestSplit split) {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('In-sample vs out-of-sample'),
          const SizedBox(height: 4),
          Text(
            'Two independent runs from the same balance. The second window '
            'knows nothing the first produced — the closest thing to an '
            'out-of-sample test one file can give you.',
            style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Window',
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 2,
                child: Text('Trades',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 3,
                child: Text('Net',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 2,
                child: Text('Win',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 3,
                child: Text('Max DD',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _splitRow('In-sample', split.inSample),
          const ListDivider(),
          _splitRow('Out-of-sample', split.outOfSample),
        ],
      ),
    );
  }

  Widget _splitRow(String label, BacktestMetrics metrics) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(color: AppColors.text, fontSize: 11.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${metrics.trades}',
              textAlign: TextAlign.right,
              style: tabular.copyWith(color: AppColors.muted, fontSize: 11.5),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _signed(metrics.netPnl),
              textAlign: TextAlign.right,
              style: tabular.copyWith(
                color: metrics.netPnl >= 0
                    ? AppColors.success
                    : AppColors.danger,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _pct(metrics.winRate),
              textAlign: TextAlign.right,
              style: tabular.copyWith(color: AppColors.muted, fontSize: 11.5),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _pct(metrics.maxDrawdownPct),
              textAlign: TextAlign.right,
              style: tabular.copyWith(color: AppColors.muted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assumptionsCard(List<String> assumptions) {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Assumptions'),
          const SizedBox(height: 8),
          for (final assumption in assumptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 13, color: AppColors.faint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      assumption,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tradesCard(List<BacktestTrade> trades) {
    final recent = trades.reversed.take(100).toList();
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Trades (${trades.length})'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Side',
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 4,
                child: Text('Entry',
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 3,
                child: Text('Lots',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 4,
                child: Text('P&L',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
              Expanded(
                flex: 3,
                child: Text('Why',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ),
            ],
          ),
          for (final trade in recent) ...[
            const ListDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      trade.isLong ? 'LONG' : 'SHORT',
                      style: tabular.copyWith(
                        color: trade.isLong
                            ? AppColors.success
                            : AppColors.danger,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      _day(trade.entryTime),
                      style: tabular.copyWith(
                        color: AppColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      trade.lots.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: tabular.copyWith(
                        color: AppColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      _signed(trade.pnl),
                      textAlign: TextAlign.right,
                      style: tabular.copyWith(
                        color: trade.pnl >= 0
                            ? AppColors.success
                            : AppColors.danger,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      trade.exitReason,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.faint, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------- saved runs

  Widget _savedCard() {
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SectionTitle(
              title: 'Saved runs',
              subtitle: 'Runs from this account, on any device.',
              trailing: _loadingRuns
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ),
          if (_runs.isEmpty && !_loadingRuns)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No saved runs yet.',
                style: TextStyle(color: AppColors.faint, fontSize: 12),
              ),
            ),
          for (final run in _runs) ...[
            const SizedBox(height: 4),
            const ListDivider(),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _busy ? null : () => _openSaved(run),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              run.name.isEmpty ? '${run.symbol} run' : run.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${run.symbol} · ${run.strategyId} · '
                              '${_day(run.createdAt)} · '
                              '${run.metrics.trades} trades',
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
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _signed(run.metrics.netPnl),
                    style: tabular.copyWith(
                      color: run.metrics.netPnl >= 0
                          ? AppColors.success
                          : AppColors.danger,
                      fontSize: 11.5,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete ${run.name}',
                    onPressed: _busy ? null : () => _deleteSaved(run),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- formatting

  String _signed(double value) =>
      value > 0 ? '+${money(value)}' : money(value);

  String _pct(double value, [int digits = 1]) =>
      '${value.toStringAsFixed(digits)}%';

  String _ratio(double? value) =>
      value == null ? '∞' : value.toStringAsFixed(2);

  String _day(DateTime? value) =>
      value == null ? '—' : DateFormat('d MMM yyyy').format(value.toLocal());

  String _dayRange(DateTime? from, DateTime? to) =>
      '${_day(from)} → ${_day(to)}';
}

/// Min/max scaled equity line with a soft fill — the same shape the web report
/// draws, minus the dependency a charting package would add.
class _EquityCurvePainter extends CustomPainter {
  const _EquityCurvePainter({
    required this.values,
    required this.color,
    required this.fill,
  });

  final List<double> values;
  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    var min = values.first;
    var max = values.first;
    for (final value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final span = (max - min).abs() < 1e-9 ? 1.0 : max - min;

    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          index / (values.length - 1) * size.width,
          size.height - (values[index] - min) / span * size.height,
        ),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill, fill.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EquityCurvePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.fill != fill;
}
