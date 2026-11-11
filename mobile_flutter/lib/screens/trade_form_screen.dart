import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/format.dart';
import '../core/instruments.dart';
import '../core/pnl.dart';
import '../core/strategy_colors.dart';
import '../core/trade_exit.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import '../services/market_data.dart';
import '../services/telemetry.dart';
import '../services/media_service.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'chart_picker_screen.dart';
import 'media_viewer_screen.dart';
import 'symbol_picker_screen.dart';

class TradeFormScreen extends StatefulWidget {
  const TradeFormScreen({super.key, this.tradeId, this.api});

  final String? tradeId;

  /// Injectable so the layout can be laid out in a test without a Supabase
  /// client; the app leaves it null and builds its own.
  final JournalApi? api;

  @override
  State<TradeFormScreen> createState() => _TradeFormScreenState();
}

class _TradeFormScreenState extends State<TradeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final JournalApi _api = widget.api ?? JournalApi();
  late final MediaService _media = MediaService(_api);

  final _symbol = TextEditingController();
  final _entry = TextEditingController();
  final _lots = TextEditingController();
  final _stop = TextEditingController();
  final _take = TextEditingController();
  final _commission = TextEditingController();
  final _swap = TextEditingController();
  final _strategy = TextEditingController();
  final _notes = TextEditingController();
  final _tagDraft = TextEditingController();

  String _type = 'BUY';
  DateTime? _openTime;
  DateTime? _closeTime;

  /// Where the market closed the trade, found from the candles after entry —
  /// never typed in. A saved trade keeps the price the broker already recorded.
  double? _exitPrice;
  ExitReason? _exitReason;
  bool _resolvingExit = false;
  List<String> _tags = const [];
  List<PendingAttachment> _pending = const [];
  List<MediaAttachment> _existing = const [];

  bool _loading = false;
  bool _saving = false;
  bool _uploading = false;
  bool _recording = false;
  int _recordSeconds = 0;
  String? _error;
  String? _createdTradeId;
  Timer? _recordTimer;
  bool _saved = false;
  List<String> _strategyLabels = const [];
  bool _strategyOpen = false;

  bool get _isEdit => widget.tradeId != null;
  String? get _userId => _api.userId;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      _loadTrade();
    }
    unawaited(_loadStrategyLabels());
  }

  /// Labels this trader has already used, offered as chips. Free text is where
  /// one model turns into three rows in the analytics matrix.
  Future<void> _loadStrategyLabels() async {
    try {
      final labels = await _api.strategyLabels();
      if (!mounted) return;
      setState(() => _strategyLabels = labels);
    } catch (_) {
      // Suggestions are optional; a database without the migration has none.
    }
  }

  /// One strategy name, one row in analytics: collapse whitespace, trim, and
  /// cap the length so a pasted paragraph cannot become a filter key.
  static String _normalizeStrategy(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  List<String> get _strategyOptions {
    final typed = _normalizeStrategy(_strategy.text).toLowerCase();
    final matches = typed.isEmpty
        ? _strategyLabels
        : _strategyLabels
            .where((label) => label.toLowerCase().contains(typed))
            .toList();
    return matches.take(8).toList();
  }

  String? get _similarStrategy {
    final typed = _normalizeStrategy(_strategy.text);
    if (typed.isEmpty || _strategyLabels.contains(typed)) return null;
    for (final label in _strategyLabels) {
      if (label.toLowerCase() == typed.toLowerCase()) return label;
    }
    return null;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    // Uploaded files are not linked to a trade until Save runs. If the user
    // backs out, remove them so the private bucket does not collect drafts.
    if (!_saved) {
      _discardUploads(_pending);
      final created = _createdTradeId;
      if (created != null) {
        unawaited(_api.deleteTrade(created).catchError((_) {}));
      }
    }
    unawaited(_media.dispose());
    for (final controller in [
      _symbol,
      _entry,
      _lots,
      _stop,
      _take,
      _commission,
      _swap,
      _strategy,
      _notes,
      _tagDraft,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTrade() async {
    try {
      final trade = await _api.loadTrade(widget.tradeId!);
      final media = await _api.attachments(widget.tradeId!);
      if (!mounted) return;
      setState(() {
        _symbol.text = asString(trade['symbol']) ?? '';
        _entry.text = _numberText(trade['entry_price']);
        _exitPrice = asNullableDouble(trade['exit_price']);
        _exitReason = null;
        _lots.text = _numberText(trade['lot_size']);
        _stop.text = _numberText(trade['stop_loss']);
        _take.text = _numberText(trade['take_profit']);
        _commission.text = _numberText(trade['commission']);
        _swap.text = _numberText(trade['swap']);
        _strategy.text = asString(trade['strategy']) ?? '';
        _notes.text = asString(trade['notes']) ?? '';
        _tags = asStringList(trade['tags']);
        _type = asString(trade['type']) == 'SELL' ? 'SELL' : 'BUY';
        _openTime = asDate(trade['open_time']);
        _closeTime = asDate(trade['close_time']);
        _existing = media;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this trade: $error';
      });
    }
  }

  String _numberText(dynamic value) {
    if (value == null) return '';
    final parsed = asDouble(value);
    if (parsed == 0) return '0';
    if (parsed == parsed.roundToDouble()) return parsed.toInt().toString();
    return parsed.toString();
  }

  double? _valueOf(TextEditingController controller) {
    final text = controller.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  double? get _pnl {
    final entry = _valueOf(_entry);
    final exit = _exitPrice;
    final lots = _valueOf(_lots);
    if (entry == null || exit == null || lots == null) return null;
    return calculatePnl(
      type: _type,
      symbol: _symbol.text.trim().isEmpty ? 'EURUSD' : _symbol.text.trim(),
      entry: entry,
      exit: exit,
      lots: lots,
      commission: _valueOf(_commission) ?? 0,
      swap: _valueOf(_swap) ?? 0,
    );
  }

  double? get _pips {
    final entry = _valueOf(_entry);
    final exit = _exitPrice;
    if (entry == null || exit == null) return null;
    final size = pipSize(
      _symbol.text.trim().isEmpty ? 'EURUSD' : _symbol.text.trim(),
    );
    return (_type == 'SELL' ? entry - exit : exit - entry) / size;
  }

  /// A stop or target on the wrong side of entry is a typo that would book a
  /// profit (or a loss) the market never offered. It blocks Save; the message
  /// spells out which side belongs to BUY and which to SELL.
  String? get _levelError {
    final entry = _valueOf(_entry);
    final stop = _valueOf(_stop);
    final take = _valueOf(_take);
    if (entry == null) return null;
    final buy = _type == 'BUY';
    if (stop != null) {
      if (buy && stop >= entry) {
        return 'For a BUY the stop loss must be below the entry.';
      }
      if (!buy && stop <= entry) {
        return 'For a SELL the stop loss must be above the entry.';
      }
    }
    if (take != null) {
      if (buy && take <= entry) {
        return 'For a BUY the take profit must be above the entry.';
      }
      if (!buy && take >= entry) {
        return 'For a SELL the take profit must be below the entry.';
      }
    }
    return null;
  }

  /// Levels are optional (the trade is then marked at the latest price), but
  /// saying so up front beats an exit that looks missing.
  String? get _levelsHint => _valueOf(_stop) == null && _valueOf(_take) == null
      ? 'Add a stop loss or a take profit, or the exit is marked at the latest price.'
      : null;

  /// Walks the candles forward from the entry and records where the market
  /// closed the trade: the target or the stop, whichever printed first.
  ///
  /// The window is read in week-long pieces: that keeps the candle size fine
  /// enough (15-minute bars) to tell which level printed first, while staying
  /// well inside the route's 62-day and 5,000-candle limits. It stops as soon as
  /// a level is hit. A trade that never reached either level keeps the latest
  /// close and says so.
  Future<bool> _resolveExitFromMarket({bool announce = false}) async {
    if (_resolvingExit) return _exitPrice != null;
    final entry = _valueOf(_entry);
    final instrument = inferInstrument(_symbol.text);
    final opened = _openTime;

    if (entry == null || instrument == null || opened == null) {
      if (announce) {
        setState(() {
          _error = instrument == null
              ? 'Pick a symbol from the list first, then find the exit.'
              : opened == null
                  ? 'Set the opened time — the candles after it decide the exit.'
                  : 'Enter the entry price first.';
        });
      }
      return false;
    }

    final to = DateTime.now().toUtc();
    final from = opened.toUtc();
    if (!from.isBefore(to)) {
      setState(
          () => _error = 'The opened time is in the future. Pick a past time.');
      return false;
    }

    setState(() {
      _resolvingExit = true;
      _error = null;
    });

    final service = MarketDataService();
    try {
      const chunk = Duration(days: 7);
      final collected = <Candle>[];
      ResolvedExit? resolved;
      var cursor = from;
      var guard = 0;

      // 60 weeks covers entries a year back; anything older than the feed's
      // history cannot be resolved from candles at all.
      while (cursor.isBefore(to) && guard < 60) {
        guard++;
        var end = cursor.add(chunk);
        if (end.isAfter(to)) end = to;
        final span = end.difference(cursor);
        var interval = defaultIntervalFor(span);
        if (candleCountFor(span, interval) == null) {
          interval = ChartInterval.oneDay;
        }
        final candles = await service.candles(
          instrument,
          interval,
          from: cursor,
          to: end,
          force: true,
        );
        // Adjacent windows share their boundary bar; a duplicate would let the
        // same candle decide twice.
        final seen = collected.map((bar) => bar.time).toSet();
        collected.addAll(candles.where((bar) => !seen.contains(bar.time)));

        resolved = resolveExit(
          type: _type,
          entry: entry,
          stop: _valueOf(_stop),
          take: _valueOf(_take),
          entryTime: from,
          candles: collected,
        );
        if (resolved != null && resolved.reason != ExitReason.latestPrice) {
          break;
        }
        cursor = end;
      }

      if (!mounted) return false;
      if (resolved == null) {
        setState(() {
          _error =
              'No candles were returned for that time. Check the symbol and '
              'the opened time, then try again.';
        });
        return false;
      }

      setState(() {
        _exitPrice = resolved!.price;
        _closeTime = resolved.time.toLocal();
        _exitReason = resolved.reason;
      });
      if (announce) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resolved.label)),
        );
      }
      return true;
    } on MarketDataException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The candles could not be read. Check your connection '
              'and try again.',
        );
      }
      return false;
    } finally {
      service.close();
      if (mounted) setState(() => _resolvingExit = false);
    }
  }

  bool get _windowInvalid =>
      _openTime != null &&
      _closeTime != null &&
      _closeTime!.isBefore(_openTime!);

  String get _windowDuration {
    if (_windowInvalid) return 'Exit before entry';
    if (_openTime == null || _closeTime == null) return 'Set both times';
    return durationText(_closeTime!.difference(_openTime!).inMinutes);
  }

  Future<void> _pickWindow({required bool open}) async {
    final current = open ? _openTime : _closeTime;
    final initial = current ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (open) {
        _openTime = value;
      } else {
        _closeTime = value;
      }
    });
  }

  void _addTag([String? raw]) {
    final source = (raw ?? _tagDraft.text).trim().toLowerCase();
    if (source.isEmpty) return;
    var clean = source
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (clean.isEmpty) return;
    if (clean.length > 24) clean = clean.substring(0, 24);
    if (_tags.contains(clean)) {
      _tagDraft.clear();
      return;
    }
    setState(() {
      _tags = [..._tags, clean];
      _tagDraft.clear();
    });
  }

  /// Deletes files that were uploaded but never attached to a saved trade.
  void _discardUploads(List<PendingAttachment> items) {
    for (final item in items) {
      unawaited(_api.removePending(item).catchError((_) {}));
    }
  }

  Future<void> _addImages() async {
    final userId = _userId;
    if (userId == null || _uploading || _saving) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final images = await _media.pickImages(
        userId: userId,
        tradeId: widget.tradeId,
      );
      if (!mounted) {
        _discardUploads(images);
        return;
      }
      if (_isEdit) {
        try {
          await _api.persistAttachments(
            userId: userId,
            tradeId: widget.tradeId!,
            pending: images,
          );
        } catch (_) {
          _discardUploads(images);
          rethrow;
        }
        await _reloadMedia();
      } else {
        setState(() => _pending = [..._pending, ...images]);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _takePhoto() async {
    final userId = _userId;
    if (userId == null || _uploading || _saving) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final photo = await _media.takePhoto(
        userId: userId,
        tradeId: widget.tradeId,
      );
      if (photo == null) return;
      if (!mounted) {
        _discardUploads([photo]);
        return;
      }
      if (_isEdit) {
        try {
          await _api.persistAttachments(
            userId: userId,
            tradeId: widget.tradeId!,
            pending: [photo],
          );
        } catch (_) {
          _discardUploads([photo]);
          rethrow;
        }
        await _reloadMedia();
      } else {
        setState(() => _pending = [..._pending, photo]);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addAudioFile() async {
    final userId = _userId;
    if (userId == null || _uploading || _saving) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final audio = await _media.pickAudioFile(
        userId: userId,
        tradeId: widget.tradeId,
      );
      if (audio == null) return;
      if (!mounted) {
        _discardUploads([audio]);
        return;
      }
      if (_isEdit) {
        try {
          await _api.persistAttachments(
            userId: userId,
            tradeId: widget.tradeId!,
            pending: [audio],
          );
        } catch (_) {
          _discardUploads([audio]);
          rethrow;
        }
        await _reloadMedia();
      } else {
        setState(() => _pending = [..._pending, audio]);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_saving || _uploading) return;
    if (_recording) {
      await _stopRecording();
      return;
    }
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _error = null;
      _recording = true;
      _recordSeconds = 0;
    });
    try {
      await _media.startRecording();
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordSeconds++);
        if (_recordSeconds >= 600) {
          _stopRecording();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      await _media.cancelRecording();
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final userId = _userId;
    if (userId == null) return;
    setState(() {
      _recording = false;
      _uploading = true;
    });
    try {
      final audio = await _media.stopRecording(
        userId: userId,
        tradeId: widget.tradeId,
      );
      if (!mounted) {
        _discardUploads([audio]);
        return;
      }
      if (_isEdit) {
        try {
          await _api.persistAttachments(
            userId: userId,
            tradeId: widget.tradeId!,
            pending: [audio],
          );
        } catch (_) {
          _discardUploads([audio]);
          rethrow;
        }
        await _reloadMedia();
      } else {
        setState(() => _pending = [..._pending, audio]);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _reloadMedia() async {
    if (widget.tradeId == null) return;
    final media = await _api.attachments(widget.tradeId!);
    if (mounted) setState(() => _existing = media);
  }

  Future<void> _removePending(PendingAttachment item) async {
    setState(() => _pending = _pending.where((row) => row != item).toList());
    try {
      await _api.removePending(item);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The file was removed here but could not be deleted from storage: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _removeExisting(MediaAttachment item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this file?'),
        content: Text(
          'It is deleted from storage as well as from this entry.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.removeAttachment(item);
      await _reloadMedia();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove that file: $error')),
        );
      }
    }
  }

  Future<void> _pickSymbol() async {
    final picked = await showSymbolPicker(
      context,
      selected: _symbol.text.trim().toUpperCase(),
    );
    if (picked == null || !mounted) return;
    setState(() => _symbol.text = picked);
  }

  /// Opens the live chart so the trader can pin the four levels instead of
  /// typing four prices and two timestamps.
  Future<void> _openChart() async {
    final instrument = inferInstrument(_symbol.text);
    if (instrument == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pick a symbol from the list first, then open the chart.',
          ),
        ),
      );
      return;
    }
    final selection = await Navigator.of(context).push<ChartSelection>(
      MaterialPageRoute(
        builder: (_) => ChartPickerScreen(
          instrument: instrument,
          direction: _type,
          entry: _valueOf(_entry),
          stop: _valueOf(_stop),
          take: _valueOf(_take),
        ),
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      // A long/short position tool carries its own side; follow it, so picking
      // a short box never fills a long trade with the stop on the wrong side.
      final direction = selection.direction?.toUpperCase();
      if (direction == 'SELL' || direction == 'BUY') _type = direction!;
      if (selection.entry != null) {
        _entry.text = chartPrice(selection.entry!, instrument);
      }
      if (selection.stop != null) {
        _stop.text = chartPrice(selection.stop!, instrument);
      }
      if (selection.take != null) {
        _take.text = chartPrice(selection.take!, instrument);
      }
      // The exit is not a level to pin: it is where the market hit the stop or
      // the target first, so the app finds it from the candles afterwards.
      if (selection.entryTime != null) _openTime = selection.entryTime;
      _exitPrice = null;
      _exitReason = null;
      _closeTime = null;
    });
    if (_levelsHint == null) unawaited(_resolveExitFromMarket());
  }

  /// The exit, as the market delivered it. It is not a text field on purpose:
  /// a typed exit is where a losing sell turns into a "profit".
  Widget _exitRow() {
    final price = _exitPrice;
    final reason = _exitReason;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            price == null
                ? 'Not found yet'
                : chartPrice(
                    price,
                    inferInstrument(_symbol.text) ?? inferInstrument('EURUSD')!,
                  ),
            style: tabular.copyWith(
              color: price == null ? AppColors.faint : AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            price == null
                ? 'The app reads the candles after entry and takes whichever '
                    'of the two levels the market hit first.'
                : '${reason?.label ?? 'Saved exit'}'
                    '${_closeTime == null ? '' : ' · ${dayOf(_closeTime)} ${timeOf(_closeTime)}'}',
            style: TextStyle(
              color: price == null ? AppColors.faint : AppColors.muted,
              fontSize: kMinLabelSize,
              height: 1.4,
            ),
          ),
          // Its own line, full width: at a 2x text size a side-by-side button
          // is what pushed this row past the card edge.
          Align(
            alignment: Alignment.centerLeft,
            child: _resolvingExit
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: () => _resolveExitFromMarket(announce: true),
                    child: Text(price == null ? 'Find exit' : 'Find again'),
                  ),
          ),
        ],
      ),
    );
  }

  /// A quiet label above a group of fields, so one card can hold prices, levels
  /// and costs without reading as a single undifferentiated grid of numbers.
  Widget _fieldGroup(String title) {
    // A full-width rule under the label rather than beside it: at a 2x text size
    // the label and a trailing line together were wider than the card, and an
    // underline cannot run out of room.
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withAlpha(120)),
        ),
      ),
      child: Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.faint,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_windowInvalid) {
      setState(() => _error = 'The exit time cannot be before the entry time.');
      return;
    }
    final levelError = _levelError;
    if (levelError != null) {
      setState(() => _error = levelError);
      return;
    }
    final userId = _userId;
    if (userId == null) {
      setState(() => _error = 'Your session expired. Sign in again.');
      return;
    }

    final entry = _valueOf(_entry);
    final lots = _valueOf(_lots);
    if (entry == null || lots == null) {
      setState(
        () => _error = 'Enter the entry price and the size before saving.',
      );
      return;
    }
    // The exit is read from the market, never typed. A saved trade that was
    // reopened keeps its broker exit and needs no second lookup.
    if (_exitPrice == null) {
      if (_openTime == null) {
        setState(
          () =>
              _error = 'Set the opened time — the candles after it decide the '
                  'exit price and time.',
        );
        return;
      }
      final resolved = await _resolveExitFromMarket();
      if (!resolved || _exitPrice == null) return;
    }
    if (!mounted) return;
    final exit = _exitPrice!;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'symbol': _symbol.text.trim().toUpperCase(),
      'type': _type,
      'entry_price': entry,
      'exit_price': exit,
      'lot_size': lots,
      'stop_loss': _valueOf(_stop),
      'take_profit': _valueOf(_take),
      'pnl': _pnl ?? 0,
      'commission': _valueOf(_commission) ?? 0,
      'swap': _valueOf(_swap) ?? 0,
      'strategy': _normalizeStrategy(_strategy.text).isEmpty
          ? null
          : _normalizeStrategy(_strategy.text),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'tags': _tags.isEmpty ? null : _tags,
      'open_time': _openTime?.toUtc().toIso8601String(),
      'close_time': _closeTime?.toUtc().toIso8601String(),
    };

    try {
      if (_isEdit) {
        await _api
            .updateTrade(widget.tradeId!, payload)
            .timeout(const Duration(seconds: 25));
        if (!mounted) return;
        _saved = true;
        Telemetry.event('trade_saved', {'mode': 'edit'});
        Navigator.pop(context, true);
        return;
      }

      var tradeId = _createdTradeId;
      if (tradeId == null) {
        tradeId = await _api
            .createTrade({...payload, 'user_id': userId}).timeout(
                const Duration(seconds: 25));
        _createdTradeId = tradeId;
      }
      if (_pending.isNotEmpty) {
        await _api
            .persistAttachments(
              userId: userId,
              tradeId: tradeId,
              pending: _pending,
            )
            .timeout(const Duration(seconds: 25));
      }
      if (!mounted) return;
      _saved = true;
      // The activation step: a trader who saves one trade has a journal. The
      // count of accounts that reach this, against paywall_view, is the whole
      // funnel until payments exist.
      Telemetry.event('trade_saved', {'mode': 'create'});
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final savedNote = _createdTradeId != null
          ? ' The trade itself was saved — press Save again to retry the media.'
          : '';
      final message = error is TimeoutException
          ? 'The save request timed out. Check your connection and press Save again.'
          : error.toString().replaceFirst('Exception: ', '');
      setState(() => _error = 'Could not save: $message$savedNote');
    } finally {
      // Never leave the Save button spinning: every exit path lands here.
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final pnl = _pnl;
    final pips = _pips;

    return Scaffold(
      appBar: AppBar(
        title: _isEdit
            ? Hero(
                tag: 'trade-${widget.tradeId}',
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(
                    _symbol.text.isEmpty ? 'Edit entry' : _symbol.text,
                  ),
                ),
              )
            : const Text('New entry'),
        actions: [
          TextButton(
            onPressed: _saving || _uploading || _recording ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            if (_error != null) ...[
              _ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: 10),
            ],
            FlatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: 'Instrument'),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _symbol,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Symbol',
                      hintText: 'EURUSD',
                      suffixIcon: IconButton(
                        tooltip: 'Pick an instrument',
                        onPressed: _pickSymbol,
                        icon: Icon(
                          Icons.expand_more,
                          size: 20,
                          color: AppColors.faint,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'A symbol is required.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _TypeButton(
                          label: 'BUY',
                          active: _type == 'BUY',
                          positive: true,
                          onTap: () => setState(() => _type = 'BUY'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TypeButton(
                          label: 'SELL',
                          active: _type == 'SELL',
                          positive: false,
                          onTap: () => setState(() => _type = 'SELL'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _openChart,
                    icon: const Icon(
                      Icons.candlestick_chart_outlined,
                      size: 16,
                    ),
                    label: const Text('Pin levels from chart'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _strategy,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() => _strategyOpen = true),
                    onTap: () => setState(() => _strategyOpen = true),
                    decoration: InputDecoration(
                      labelText: 'Strategy',
                      hintText: 'London breakout',
                      suffixIcon: _strategyLabels.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Saved strategies',
                              icon: Icon(
                                _strategyOpen
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                color: AppColors.muted,
                              ),
                              onPressed: () => setState(
                                () => _strategyOpen = !_strategyOpen,
                              ),
                            ),
                    ),
                  ),
                  if (_strategyOpen && _strategyOptions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          for (var index = 0;
                              index < _strategyOptions.length;
                              index++) ...[
                            if (index > 0)
                              Divider(
                                height: 1,
                                color: AppColors.border.withAlpha(120),
                              ),
                            InkWell(
                              onTap: () => setState(() {
                                _strategy.text = _strategyOptions[index];
                                _strategy.selection = TextSelection.collapsed(
                                  offset: _strategyOptions[index].length,
                                );
                                _strategyOpen = false;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: strategyColor(
                                          'strategy:${_strategyOptions[index]}',
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _strategyOptions[index],
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.text,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                    if (_normalizeStrategy(_strategy.text) ==
                                        _strategyOptions[index])
                                      Icon(
                                        Icons.check,
                                        size: 14,
                                        color: AppColors.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_similarStrategy != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'You already use “$_similarStrategy”. Pick the existing '
                      'spelling so its statistics stay together.',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: kMinLabelSize,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            FlatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: 'Execution'),
                  const SizedBox(height: 10),
                  // Prices, levels, size and costs are three different questions.
                  // Laid out as one 2x4 grid they read as a single block of
                  // numbers, and the broker costs were mixed in with the trade.
                  _fieldGroup('Prices'),
                  _NumberField(
                    controller: _entry,
                    label: 'Entry price',
                    positive: true,
                    onChanged: () => setState(() {}),
                  ),
                  _fieldGroup('Stop & target'),
                  Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          controller: _stop,
                          label: 'Stop loss',
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NumberField(
                          controller: _take,
                          label: 'Take profit',
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  if (_levelError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _levelError!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: kMinLabelSize,
                          height: 1.4,
                        ),
                      ),
                    )
                  else if (_levelsHint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _levelsHint!,
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: kMinLabelSize,
                          height: 1.4,
                        ),
                      ),
                    ),
                  _fieldGroup('Exit'),
                  _exitRow(),
                  _fieldGroup('Size & costs'),
                  _NumberField(
                    controller: _lots,
                    label: 'Size (lots)',
                    positive: true,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          controller: _commission,
                          label: 'Commission',
                          signed: true,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NumberField(
                          controller: _swap,
                          label: 'Swap',
                          signed: true,
                          onChanged: () => setState(() {}),
                        ),
                      ),
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
                    title: 'Time window',
                    subtitle:
                        'Entry and exit time drive the hour and session report.',
                  ),
                  const SizedBox(height: 8),
                  _WindowRow(
                    label: 'Opened',
                    value: _openTime == null
                        ? 'Not set'
                        : '${dayOf(_openTime)} · ${timeOf(_openTime)}',
                    onTap: () => _pickWindow(open: true),
                    onClear: _openTime == null
                        ? null
                        : () => setState(() => _openTime = null),
                  ),
                  const SizedBox(height: 6),
                  // The close is not picked by hand: it is the candle on which
                  // the stop or the target was reached.
                  _WindowRow(
                    label: 'Closed',
                    value: _closeTime == null
                        ? 'Found with the exit'
                        : '${dayOf(_closeTime)} · ${timeOf(_closeTime)}',
                    onTap: () => _resolveExitFromMarket(announce: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: AppColors.faint,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Time in market',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 'Exit before entry' and 'Set both times' are the longest
                      // this ever gets, and at a 2x text size they pushed the row
                      // past the card edge.
                      Flexible(
                        child: Text(
                          _windowDuration,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tabular.copyWith(
                            color: _windowInvalid
                                ? AppColors.danger
                                : AppColors.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
                    title: 'Journal',
                    subtitle:
                        'What was the setup, and what did you actually do?',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notes,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'The idea, the trigger, how you managed it.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SectionTitle(
                    title: 'Photos & voice notes',
                    subtitle:
                        'A chart screenshot and a spoken note are worth more than a paragraph later.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploading || _saving ? null : _addImages,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 15,
                        ),
                        label: const Text('Gallery'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _uploading || _saving ? null : _takePhoto,
                        icon: const Icon(Icons.photo_camera_outlined, size: 15),
                        label: const Text('Camera'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _uploading || _saving ? null : _toggleRecording,
                        icon: Icon(
                          _recording ? Icons.stop : Icons.mic_none,
                          size: 15,
                          color: _recording ? AppColors.danger : null,
                        ),
                        label: Text(
                          _recording
                              ? 'Stop ${clockText(_recordSeconds)}'
                              : 'Record',
                          style: TextStyle(
                            color: _recording ? AppColors.danger : null,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: BorderSide(
                            color: _recording
                                ? AppColors.danger
                                : AppColors.borderStrong,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _uploading || _saving ? null : _addAudioFile,
                        icon: const Icon(Icons.audio_file_outlined, size: 15),
                        label: const Text('Audio file'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ],
                  ),
                  if (_uploading) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Uploading…',
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_pending.isNotEmpty || _existing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _MediaGrid(
                      pending: _pending,
                      existing: _existing,
                      onRemovePending: _removePending,
                      onRemoveExisting: _removeExisting,
                      signedUrl: _api.signedUrl,
                    ),
                  ],
                  const SizedBox(height: 12),
                  const SectionTitle(title: 'Tags'),
                  const SizedBox(height: 6),
                  if (_tags.isEmpty)
                    Text(
                      'No tags yet — they drive the edge report.',
                      style: TextStyle(color: AppColors.faint, fontSize: 10.5),
                    )
                  else
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final tag in _tags)
                          Container(
                            padding: const EdgeInsets.only(left: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(20),
                              border: Border.all(
                                color: AppColors.primary.withAlpha(70),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    tag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.primaryLight,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(
                                    () => _tags = _tags
                                        .where((item) => item != tag)
                                        .toList(),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(5),
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: AppColors.primaryLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagDraft,
                          maxLength: 24,
                          decoration: const InputDecoration(
                            hintText: 'Add a tag and press enter',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: _addTag,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(46, 46),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.add, size: 18),
                        ),
                      ),
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
                  const SectionTitle(title: 'Live ticket'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ESTIMATED P&L',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                pnl == null ? '—' : signedMoney(pnl),
                                style: tabular.copyWith(
                                  color: pnl == null
                                      ? AppColors.faint
                                      : pnl >= 0
                                          ? AppColors.success
                                          : AppColors.danger,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Flexible: the duration is the widest thing here
                      // ('Exit before entry'), and unbounded it pushed the ticket
                      // row 17px past the card at a 2x text size.
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              pips == null
                                  ? '—'
                                  : '${pips.toStringAsFixed(1)} pips',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tabular.copyWith(
                                color: AppColors.text,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _windowDuration,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tabular.copyWith(
                                color: AppColors.faint,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ink,
                      ),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Save entry'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.positive = false,
    this.signed = false,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final bool positive;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      decoration: InputDecoration(labelText: label),
      // Validate as the trader types: a zero is caught next to the field instead
      // of only when Save is pressed.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) => onChanged(),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) {
          return positive ? 'Required' : null;
        }
        final parsed = double.tryParse(text.replaceAll(',', '.'));
        if (parsed == null) return 'Number';
        if (positive && parsed <= 0) return 'Must be > 0';
        return null;
      },
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.label,
    required this.active,
    required this.positive,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool positive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.danger;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color.withAlpha(22) : Colors.transparent,
          border: Border.all(
            color: active ? color.withAlpha(120) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: tabular.copyWith(color: AppColors.text, fontSize: 12),
              ),
            ),
            if (onClear != null)
              InkWell(
                onTap: onClear,
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 13, color: AppColors.faint),
                ),
              ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.pending,
    required this.existing,
    required this.onRemovePending,
    required this.onRemoveExisting,
    required this.signedUrl,
  });

  final List<PendingAttachment> pending;
  final List<MediaAttachment> existing;
  final ValueChanged<PendingAttachment> onRemovePending;
  final ValueChanged<MediaAttachment> onRemoveExisting;
  final Future<String?> Function(String path) signedUrl;

  @override
  Widget build(BuildContext context) {
    final images = pending.where((row) => row.isImage).toList();
    final audio = pending.where((row) => !row.isImage).toList();
    final existingImages = existing.where((row) => row.isImage).toList();
    final existingAudio = existing.where((row) => row.isAudio).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty || existingImages.isNotEmpty) ...[
          Text(
            'SCREENSHOTS',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in images)
                _ImageThumb(
                  bytes: item.previewBytes,
                  onRemove: () => onRemovePending(item),
                ),
              for (final item in existingImages)
                _RemoteImageThumb(
                  attachment: item,
                  signedUrl: signedUrl,
                  onRemove: () => onRemoveExisting(item),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (audio.isNotEmpty || existingAudio.isNotEmpty) ...[
          Text(
            'VOICE NOTES',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 5),
          for (final item in audio)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _PendingAudioRow(
                attachment: item,
                onRemove: () => onRemovePending(item),
              ),
            ),
          for (final item in existingAudio)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _AudioTile(
                label: item.fileName ?? 'Voice note',
                meta: '${clockText(item.durationSeconds)}'
                    '${item.sizeBytes != null ? ' · ${fileSize(item.sizeBytes!)}' : ''}',
                storagePath: item.storagePath,
                signedUrl: signedUrl,
                onRemove: () => onRemoveExisting(item),
              ),
            ),
        ],
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.bytes, required this.onRemove});

  final Uint8List? bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _ThumbFrame(
      onRemove: onRemove,
      child: bytes == null
          ? Icon(Icons.image_outlined, color: AppColors.faint, size: 20)
          : Image.memory(
              bytes!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }
}

class _RemoteImageThumb extends StatefulWidget {
  const _RemoteImageThumb({
    required this.attachment,
    required this.signedUrl,
    required this.onRemove,
  });

  final MediaAttachment attachment;
  final Future<String?> Function(String path) signedUrl;
  final VoidCallback onRemove;

  @override
  State<_RemoteImageThumb> createState() => _RemoteImageThumbState();
}

class _RemoteImageThumbState extends State<_RemoteImageThumb> {
  Future<String?>? _url;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  @override
  void didUpdateWidget(_RemoteImageThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.storagePath != widget.attachment.storagePath) {
      _loadUrl();
    }
  }

  void _loadUrl() {
    final path = widget.attachment.storagePath;
    _url = path == null ? null : widget.signedUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.attachment.storagePath;
    if (path == null) {
      return _ThumbFrame(
        onRemove: widget.onRemove,
        child: Icon(
          Icons.image_outlined,
          color: AppColors.faint,
          size: 20,
        ),
      );
    }
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasError;
        return _ThumbFrame(
          onRemove: widget.onRemove,
          onTap: url == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaViewerScreen(
                        title: widget.attachment.fileName ?? 'Screenshot',
                        imageUrl: url,
                      ),
                    ),
                  ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                )
              : url == null
                  ? Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.faint,
                      size: 20,
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stack) => Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.faint,
                        size: 20,
                      ),
                    ),
        );
      },
    );
  }
}

class _ThumbFrame extends StatelessWidget {
  const _ThumbFrame({required this.child, required this.onRemove, this.onTap});

  final Widget child;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 66,
      child: Material(
        color: AppColors.surfaceAlt,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: AppColors.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(onTap: onTap, child: child),
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.background.withAlpha(200),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 11,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAudioRow extends StatelessWidget {
  const _PendingAudioRow({required this.attachment, required this.onRemove});

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _AudioFrame(
      label: attachment.fileName,
      meta:
          '${clockText(attachment.durationSeconds)} · ${fileSize(attachment.sizeBytes)} · uploads on save',
      onRemove: onRemove,
      trailing: Icon(
        Icons.cloud_upload_outlined,
        size: 15,
        color: AppColors.faint,
      ),
    );
  }
}

class _AudioTile extends StatefulWidget {
  const _AudioTile({
    required this.label,
    required this.meta,
    required this.storagePath,
    required this.signedUrl,
    required this.onRemove,
  });

  final String label;
  final String meta;
  final String? storagePath;
  final Future<String?> Function(String path) signedUrl;
  final VoidCallback onRemove;

  @override
  State<_AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<_AudioTile> {
  AudioPlayer? _player;
  Future<String?>? _url;
  bool _playing = false;
  bool _loading = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  @override
  void didUpdateWidget(_AudioTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _loaded = false;
      _loadUrl();
    }
  }

  void _loadUrl() {
    final path = widget.storagePath;
    _url = path == null ? null : widget.signedUrl(path);
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() => _playing = false);
        player.seek(Duration.zero);
        player.pause();
      }
    });
    _player = player;
    return player;
  }

  Future<void> _toggle() async {
    final urlFuture = _url;
    if (urlFuture == null) return;
    setState(() => _loading = true);
    try {
      final url = await urlFuture;
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open that recording.')),
          );
        }
        return;
      }
      final player = _ensurePlayer();
      if (_playing) {
        await player.pause();
        if (mounted) setState(() => _playing = false);
      } else {
        if (!_loaded) {
          await player.setUrl(url);
          _loaded = true;
        }
        player.play();
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play that recording.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AudioFrame(
      label: widget.label,
      meta: widget.meta,
      onRemove: widget.onRemove,
      trailing: _loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            )
          : InkWell(
              onTap: _url == null ? null : _toggle,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  _playing ? Icons.pause : Icons.play_arrow,
                  size: 18,
                  color: _url == null ? AppColors.faint : AppColors.primary,
                ),
              ),
            ),
    );
  }
}

class _AudioFrame extends StatelessWidget {
  const _AudioFrame({
    required this.label,
    required this.meta,
    required this.onRemove,
    required this.trailing,
  });

  final String label;
  final String meta;
  final VoidCallback onRemove;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 15, color: AppColors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.faint, fontSize: 9),
                ),
              ],
            ),
          ),
          trailing,
          InkWell(
            onTap: onRemove,
            child: Padding(
              padding: EdgeInsets.all(3),
              child: Icon(
                Icons.delete_outline,
                size: 14,
                color: AppColors.faint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withAlpha(20),
        border: Border.all(color: AppColors.danger.withAlpha(90)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            child: Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.close, size: 13, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
