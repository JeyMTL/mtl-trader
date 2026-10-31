import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/chart_replay.dart';
import 'time_frame_sheet.dart';
import '../core/chart_drawings.dart';
import '../core/chart_scale.dart';
import '../core/chart_theme.dart';
import '../core/chart_view.dart';
import '../core/indicators.dart';
import '../core/instruments.dart';
import '../services/market_data.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Levels pinned on the chart. Any field may be null when the trader only
/// wanted to set some of them.
class ChartSelection {
  const ChartSelection({
    this.entry,
    this.exit,
    this.stop,
    this.take,
    this.entryTime,
    this.exitTime,
  });

  final double? entry;
  final double? exit;
  final double? stop;
  final double? take;
  final DateTime? entryTime;
  final DateTime? exitTime;

  bool get isEmpty =>
      entry == null && exit == null && stop == null && take == null;
}

enum _Marker { entry, stop, take, exit }

/// TradingView-style chart screen: the canvas owns pan, zoom, crosshair and
/// line dragging, so a finger move never rebuilds the cards around it.
class ChartPickerScreen extends StatefulWidget {
  const ChartPickerScreen({
    super.key,
    required this.instrument,
    required this.direction,
    this.entry,
    this.exit,
    this.stop,
    this.take,
  });

  final Instrument instrument;
  final String direction;
  final double? entry;
  final double? exit;
  final double? stop;
  final double? take;

  @override
  State<ChartPickerScreen> createState() => _ChartPickerScreenState();
}

class _ChartPickerScreenState extends State<ChartPickerScreen> {
  final _market = MarketDataService();

  ChartInterval _interval = ChartInterval.fiveMinutes;

  /// Drawing tools: trend lines and horizontal rays.
  DrawingTool _drawingTool = DrawingTool.none;
  List<ChartDrawing> _drawings = const [];
  DrawingDraft? _draftStart;

  /// Drawing under the trader's finger, selected for drag or delete.
  int? _selectedDrawing;

  /// Window the trader entered. Both null means the live tail.
  DateTime? _windowFrom;
  DateTime? _windowTo;

  bool get _customWindow => _windowFrom != null && _windowTo != null;

  List<Candle> _candles = const [];
  bool _loading = true;
  String? _error;
  DateTime? _updated;
  Timer? _refreshTimer;

  ChartStyle _style = ChartStyle.current;
  bool _fullscreen = false;

  ReplayCursor? _replay;
  Timer? _playTimer;
  bool _loadingOlder = false;

  /// Replay speeds, cycled by the strip's speed chip.
  static const List<double> _speeds = <double>[1, 2, 4, 8];
  int _speedIndex = 0;

  bool get _playing => _playTimer != null;

  double get _speed => _speeds[_speedIndex];

  Duration get _tick => Duration(milliseconds: (550 / _speed).round());

  /// How much history one request covers, and therefore how far a jump or a
  /// page-back reaches. A window the trader set keeps its own length.
  Duration get _rangeSpan {
    final from = _windowFrom;
    final to = _windowTo;
    if (from != null && to != null) return to.difference(from);
    return const Duration(days: 1);
  }

  _Marker _active = _Marker.entry;
  double? _entry;
  double? _exit;
  double? _stop;
  double? _take;
  DateTime? _entryTime;
  DateTime? _exitTime;

  bool get _isBuy => widget.direction.toUpperCase() != 'SELL';

  bool get _timeInvalid =>
      _entryTime != null &&
      _exitTime != null &&
      _exitTime!.isBefore(_entryTime!);

  String? get _directionWarning {
    final entry = _entry;
    if (entry == null) return null;
    final stop = _stop;
    final take = _take;
    if (stop != null && _isBuy && stop >= entry) {
      return 'For a BUY the stop is normally below entry.';
    }
    if (stop != null && !_isBuy && stop <= entry) {
      return 'For a SELL the stop is normally above entry.';
    }
    if (take != null && _isBuy && take <= entry) {
      return 'For a BUY the target is normally above entry.';
    }
    if (take != null && !_isBuy && take >= entry) {
      return 'For a SELL the target is normally below entry.';
    }
    return null;
  }

  /// Candles up to the replay cursor, or all of them when replay is off.
  List<Candle> get _visibleCandles {
    final replay = _replay;
    if (replay == null || replay.visible >= _candles.length) return _candles;
    return _candles.sublist(0, replay.visible);
  }

  Candle? get _lastVisible =>
      _visibleCandles.isEmpty ? null : _visibleCandles.last;

  double? get _changePercent {
    final candles = _visibleCandles;
    if (candles.length < 2) return null;
    final first = candles.first.open;
    if (first == 0) return null;
    return (candles.last.close - first) / first * 100;
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _exit = widget.exit;
    _stop = widget.stop;
    _take = widget.take;

    // Paint whatever the cache already holds, then refresh in the background.
    final cached = _market.cached(widget.instrument, _interval);
    if (cached != null && cached.isNotEmpty) {
      _candles = cached;
      _loading = false;
    }    _load(silent: _candles.isNotEmpty, force: true);
    _startRefreshTimer();
    _restoreDrawings();
    _restoreLayout();
  }

  /// Every instrument remembers its own studies, panes and scale.
  Future<void> _restoreLayout() async {
    final layout = await ChartStyle.loadLayout(widget.instrument.symbol);
    if (!mounted) return;
    setState(() => _style = layout);
  }

  Future<void> _restoreDrawings() async {
    final loaded = await ChartDrawingStore.load(widget.instrument.symbol);
    if (!mounted || loaded.isEmpty) return;
    setState(() => _drawings = loaded);
  }

  /// Persists on every change so a back gesture cannot lose the trader's work.
  void _commitDrawings(List<ChartDrawing> next) {
    setState(() {
      _drawings = next;
      _selectedDrawing = null;
    });
    unawaited(ChartDrawingStore.save(widget.instrument.symbol, next));
  }

  /// Repaints a drawing while it is being dragged; the write waits for the
  /// finger to lift so a pan does not queue dozens of disk writes.
  void _moveDrawing(int index, ChartDrawing drawing) {
    if (index < 0 || index >= _drawings.length) return;
    final next = [..._drawings];
    next[index] = drawing;
    setState(() => _drawings = next);
  }

  void _finishDrawingMove() {
    unawaited(ChartDrawingStore.save(widget.instrument.symbol, _drawings));
  }

  void _deleteDrawing(int index) {
    if (index < 0 || index >= _drawings.length) return;
    _commitDrawings([..._drawings]..removeAt(index));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _playTimer?.cancel();
    _market.close();
    // Leaving by the back gesture must not strand immersive mode.
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  /// Polls while the chart shows the live tail.
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _load(silent: true),
    );
  }

  /// A past window never changes, so it is fetched once and not polled.
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    try {
      final candles = await _market.candles(
        widget.instrument,
        _interval,
        from: _windowFrom,
        to: _windowTo,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _candles = candles;
        _loading = false;
        _error = null;
        _updated = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      // A failed background refresh must not wipe a chart the trader can use.
      if (silent && _candles.isNotEmpty) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load(force: true);
  }

  /// Loads exactly the span the trader entered and stops polling, because a past
  /// window never changes.
  Future<void> _applyWindow(
    DateTime from,
    DateTime to,
    ChartInterval interval,
  ) async {
    _stopPlay();
    final cached =
        _market.cached(widget.instrument, interval, from: from, to: to);
    _stopRefreshTimer();
    setState(() {
      _interval = interval;
      _windowFrom = from;
      _windowTo = to;
      _replay = null;
      _error = null;
      _candles = cached ?? const [];
      _loading = cached == null || cached.isEmpty;
    });
    final loaded = await _loadWindow(start: from, end: to);
    if (!mounted || loaded == null) return;
    if (loaded.isEmpty) {
      setState(
        () => _error = 'No candles in that time frame. Try a wider window.',
      );
    }
  }

  /// Back to the live tail, with polling.
  void _setLive() {
    if (!_customWindow) return;
    _stopPlay();
    setState(() {
      _windowFrom = null;
      _windowTo = null;
      _replay = null;
      _error = null;
    });
    _startRefreshTimer();
    _load(force: true);
  }

  String _stamp(DateTime value) =>
      DateFormat('d MMM HH:mm').format(value.toLocal());

  void _setLevel(_Marker marker, double price) {
    switch (marker) {
      case _Marker.entry:
        _entry = price;
        break;
      case _Marker.stop:
        _stop = price;
        break;
      case _Marker.take:
        _take = price;
        break;
      case _Marker.exit:
        _exit = price;
        break;
    }
  }

  void _pin(_Marker marker, double price, DateTime time) {
    setState(() {
      _setLevel(marker, price);
      if (marker == _Marker.entry) _entryTime = time;
      if (marker == _Marker.exit) _exitTime = time;
      _active = switch (marker) {
        _Marker.entry => _Marker.stop,
        _Marker.stop => _Marker.take,
        _Marker.take => _Marker.exit,
        _Marker.exit => _Marker.exit,
      };
    });
  }

  /// Applies a drag from the canvas. Entry and exit are points on the chart, so
  /// their time moves with the price; stop and take only carry a price.
  void _levelMoved(_Marker marker, double price, DateTime? time) {
    setState(() {
      _setLevel(marker, price);
      if (time == null) return;
      if (marker == _Marker.entry) _entryTime = time;
      if (marker == _Marker.exit) _exitTime = time;
    });
  }

  void _clear(_Marker marker) {
    setState(() {
      switch (marker) {
        case _Marker.entry:
          _entry = null;
          _entryTime = null;
          break;
        case _Marker.stop:
          _stop = null;
          break;
        case _Marker.take:
          _take = null;
          break;
        case _Marker.exit:
          _exit = null;
          _exitTime = null;
          break;
      }
    });
  }

  void _reset() {
    setState(() {
      _entry = null;
      _exit = null;
      _stop = null;
      _take = null;
      _entryTime = null;
      _exitTime = null;
      _active = _Marker.entry;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back leaves the fullscreen canvas instead of the chart screen.
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: _fullscreen ? _fullscreenView() : _screenView(),
    );
  }

  Widget _screenView() {
    final instrument = widget.instrument;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${instrument.symbol} · chart'),
        actions: [
          IconButton(
            tooltip: 'Drawing tools',
            onPressed: _openDrawingSheet,
            icon: const Icon(Icons.draw_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Market replay',
            onPressed: _candles.length < 12 ? null : _toggleReplayMode,
            icon: const Icon(Icons.replay, size: 20),
          ),
          IconButton(
            tooltip: 'Chart style',
            onPressed: _openStyleSheet,
            icon: const Icon(Icons.tune, size: 20),
          ),
          IconButton(
            tooltip: 'Fullscreen',
            onPressed: _candles.isEmpty ? null : _toggleFullscreen,
            icon: const Icon(Icons.fullscreen, size: 21),
          ),
          IconButton(
            tooltip: 'Clear levels',
            onPressed: _candles.isEmpty ? null : _reset,
            icon: const Icon(Icons.restart_alt, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              children: [
                _header(instrument),
                const SizedBox(height: 8),
                _timeFrame(),
                if (_drawingTool != DrawingTool.none) ...[
                  const SizedBox(height: 6),
                  _drawingBanner(),
                ],
                if (_replay != null) ...[
                  const SizedBox(height: 6),
                  _replayStrip(),
                ],
                const SizedBox(height: 8),
                FlatCard(
                  padding: EdgeInsets.zero,
                  color: _style.background,
                  child: Column(
                    children: [
                      _chartPanel(instrument),
                      _chartFooter(),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _disclaimer(),
                const SizedBox(height: 10),
                _levelsCard(),
                if (_timeInvalid) ...[
                  const SizedBox(height: 8),
                  const _Warning(
                    text: 'The exit time is before the entry time.',
                  ),
                ],
                if (_directionWarning != null) ...[
                  const SizedBox(height: 8),
                  _Warning(text: _directionWarning!),
                ],
                if (_directionWarning != null || _timeInvalid) ...[
                  const SizedBox(height: 4),
                  Text(
                    'You can still save it — this is only a heads-up.',
                    style: TextStyle(color: AppColors.faint, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _fullscreenView() {
    return Scaffold(
      backgroundColor: _style.background,
      body: SafeArea(
        child: Column(
          children: [
            _fullscreenHeader(widget.instrument),
            Expanded(
              child: _chartPanel(widget.instrument, expand: true),
            ),
            _fullscreenControls(),
          ],
        ),
      ),
    );
  }

  Widget _fullscreenHeader(Instrument instrument) {
    final last = _lastVisible?.close;
    final change = _changePercent;
    final parts = <String>[
      if (last != null) chartPrice(last, instrument),
      if (change != null)
        '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instrument.symbol,
                  style: TextStyle(
                    color: _style.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  parts.isEmpty
                      ? '${instrument.name} · ${_interval.key}'
                      : '${parts.join('  ')}  · ${_interval.key}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tabular.copyWith(
                    color: _style.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Drawing tools',
            onPressed: _openDrawingSheet,
            icon: Icon(Icons.draw_outlined, size: 20, color: _style.muted),
          ),
          IconButton(
            tooltip: 'Market replay',
            onPressed: _candles.length < 12 ? null : _toggleReplayMode,
            icon: Icon(Icons.replay, size: 20, color: _style.muted),
          ),
          IconButton(
            tooltip: 'Chart style',
            onPressed: _openStyleSheet,
            icon: Icon(Icons.tune, size: 20, color: _style.muted),
          ),
          IconButton(
            tooltip: 'Exit fullscreen',
            onPressed: _toggleFullscreen,
            icon: Icon(Icons.fullscreen_exit, size: 21, color: _style.muted),
          ),
        ],
      ),
    );
  }

  Widget _fullscreenControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        children: [
          if (_replay != null) ...[
            _replayStrip(overlay: true),
            const SizedBox(height: 6),
          ],
          _timeFrame(overlay: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tap to set ${_labelFor(_active)} · hold a line to move it and its time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _style.muted, fontSize: 9.5),
                ),
              ),
              Text(
                _style.name,
                style: TextStyle(
                  color: _style.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartPanel(Instrument instrument, {bool expand = false}) {
    if (_loading) {
      if (expand) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return const SizedBox(
        height: _TradingChartPainter.height,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) return _chartError(expand: expand);
    return _ChartCanvas(
      candles: _visibleCandles,
      interval: _interval,
      decimals: instrument.decimals,
      symbol: instrument.symbol,
      style: _style,
      // Null height means "fill whatever the parent gives me", which is how
      // the fullscreen canvas grows without knowing the screen size here.
      height: expand ? null : _TradingChartPainter.height,
      active: _active,
      entry: _entry,
      stop: _stop,
      take: _take,
      exit: _exit,
      entryTime: _entryTime,
      exitTime: _exitTime,
      onSelect: (marker) => setState(() => _active = marker),
      onPin: _pin,
      onLevelMoved: _levelMoved,
      drawTool: _drawingTool,
      drawings: _drawings,
      draftStart: _draftStart,
      onDraw: _onDraw,
      selectedDrawing: _selectedDrawing,
      onDrawingSelected: (index) =>
          setState(() => _selectedDrawing = index),
      onDrawingMoved: _moveDrawing,
      onDrawingMoveEnd: _finishDrawingMove,
    );
  }

  Future<void> _jumpToDate() async {
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 365));
    final earliest = _candles.isEmpty
        ? now.subtract(_rangeSpan)
        : _candles.first.time.toLocal();
    final initial = earliest.isBefore(first) ? first : earliest;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: first,
      lastDate: now,
      helpText: 'Replay from a date',
    );
    if (picked == null || !mounted) return;

    final start = DateTime(picked.year, picked.month, picked.day);
    final loaded = await _loadWindow(start: start, end: start.add(_rangeSpan));
    if (!mounted) return;
    if (loaded == null || loaded.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No candles for ${DateFormat('d MMM yyyy').format(start)}.',
          ),
        ),
      );
      return;
    }

    // A past window would be overwritten by the next live refresh.
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _stopPlay();
    setState(() => _replay = ReplayCursor.start(count: _candles.length));
  }

  /// Replaces the series with the requested window. Null means the request
  /// failed (the error has already been shown); an empty list means the window
  /// simply has no candles — a weekend, a holiday, or before the instrument
  /// existed.
  Future<List<Candle>?> _loadWindow({
    required DateTime start,
    required DateTime end,
  }) async {
    setState(() => _loading = true);
    try {
      final candles = await _market.candles(
        widget.instrument,
        _interval,
        from: start,
        to: end,
        force: true,
      );
      if (!mounted) return null;
      setState(() {
        _candles = candles;
        _loading = false;
        _error = null;
      });
      return candles;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return null;
    }
  }

  /// Fetches the window just before the loaded one, prepends it and keeps the
  /// cursor on the same candle so the replay does not jump.
  Future<void> _loadOlder() async {
    final replay = _replay;
    if (replay == null || _candles.isEmpty || _loadingOlder) return;

    final oldest = _candles.first.time;
    setState(() => _loadingOlder = true);
    try {
      final older = await _market.candles(
        widget.instrument,
        _interval,
        from: oldest.subtract(_rangeSpan),
        to: oldest,
        force: true,
      );
      if (!mounted) return;

      // The request ends where the loaded series starts, so drop the shared bar.
      final fresh =
          older.where((candle) => candle.time.isBefore(oldest)).toList();
      if (fresh.isEmpty) {
        setState(() => _loadingOlder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No earlier candles for this range.')),
        );
        return;
      }

      setState(() {
        _candles = [...fresh, ..._candles];
        _replay = ReplayCursor(
          count: _candles.length,
          index: replay.index + fresh.length,
        );
        _loadingOlder = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _cycleSpeed() {
    final wasPlaying = _playing;
    _stopPlay();
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    if (wasPlaying) _togglePlay();
  }

  void _toggleReplayMode() {
    if (_replay == null) {
      _enterReplay();
    } else {
      _exitReplay();
    }
  }

  void _enterReplay() {
    if (_candles.length < 12) return;
    // A live refresh would keep appending candles past the replay cursor.
    _refreshTimer?.cancel();
    _refreshTimer = null;
    setState(() => _replay = ReplayCursor.start(count: _candles.length));
  }

  void _exitReplay() {
    _stopPlay();
    setState(() {
      _replay = null;
      _loadingOlder = false;
    });
    if (!_customWindow) _startRefreshTimer();
    _load(silent: _candles.isNotEmpty);
  }

  void _step(int delta) {
    final replay = _replay;
    if (replay == null) return;
    setState(() => _replay = delta >= 0 ? replay.next() : replay.previous());
    if (_replay!.atEnd) _stopPlay();
  }

  void _togglePlay() {
    if (_playing) {
      setState(_stopPlay);
      return;
    }
    final replay = _replay;
    if (replay == null || replay.atEnd) return;
    setState(() {
      _playTimer = Timer.periodic(_tick, (_) {
        if (!mounted) return;
        final current = _replay;
        if (current == null || current.atEnd) {
          _stopPlay();
          setState(() {});
          return;
        }
        setState(() => _replay = current.next());
      });
    });
  }

  void _stopPlay() {
    _playTimer?.cancel();
    _playTimer = null;
  }

  Widget _replayStrip({bool overlay = false}) {
    final replay = _replay;
    final candles = _visibleCandles;
    if (replay == null || candles.isEmpty) return const SizedBox.shrink();

    final ink = overlay ? _style.text : AppColors.text;
    final muted = overlay ? _style.muted : AppColors.muted;
    final accent = overlay ? _style.bull : AppColors.primary;
    final surface = overlay ? _style.background : AppColors.surface;
    final border = overlay ? _style.axis : AppColors.border;
    final off = muted.withAlpha(90);
    final candle = candles[replay.index];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          IconButton(
            // At the first loaded candle there is nothing to step back to, so
            // the same button pages further back through history instead.
            tooltip: replay.atStart ? 'Load earlier candles' : 'Previous bar',
            visualDensity: VisualDensity.compact,
            onPressed: replay.atStart
                ? (_loadingOlder ? null : _loadOlder)
                : () => _step(-1),
            icon: _loadingOlder
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: accent,
                    ),
                  )
                : Icon(
                    replay.atStart ? Icons.history : Icons.skip_previous,
                    size: 18,
                    color: replay.atStart ? accent : ink,
                  ),
          ),
          IconButton(
            tooltip: _playing ? 'Pause replay' : 'Play replay',
            visualDensity: VisualDensity.compact,
            onPressed: replay.atEnd ? null : _togglePlay,
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              size: 20,
              color: replay.atEnd ? off : accent,
            ),
          ),
          IconButton(
            tooltip: 'Next bar',
            visualDensity: VisualDensity.compact,
            onPressed: replay.atEnd ? null : () => _step(1),
            icon: Icon(
              Icons.skip_next,
              size: 18,
              color: replay.atEnd ? off : ink,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              '${DateFormat('d MMM HH:mm').format(candle.time.toLocal())}'
              ' · ${replay.visible}/${replay.count}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tabular.copyWith(
                color: ink,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          InkWell(
            onTap: _cycleSpeed,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Text(
                '${_speed.toStringAsFixed(0)}×',
                style: tabular.copyWith(
                  color: accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Jump to a date',
            visualDensity: VisualDensity.compact,
            onPressed: _jumpToDate,
            icon: Icon(Icons.event, size: 17, color: muted),
          ),
          TextButton(
            onPressed: _exitReplay,
            style: TextButton.styleFrom(
              foregroundColor: muted,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Widget _drawingBanner() {
    final hint = _drawingTool == DrawingTool.trend
        ? (_draftStart == null
            ? 'Tap the first point of the trend line.'
            : 'Tap the second point to finish the line.')
        : 'Tap a price for the horizontal ray.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.primary.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(Icons.draw_outlined, size: 14, color: AppColors.primaryLight),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(
                color: AppColors.primaryLight,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _drawingTool = DrawingTool.none;
              _draftStart = null;
            }),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDrawingSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timeline, size: 20),
              title: const Text('Trend line'),
              subtitle: const Text('Tap two points on the chart'),
              onTap: () => Navigator.of(sheetContext).pop('trend'),
            ),
            ListTile(
              leading: const Icon(Icons.horizontal_rule, size: 20),
              title: const Text('Horizontal ray'),
              subtitle: const Text('Tap a price on the chart'),
              onTap: () => Navigator.of(sheetContext).pop('ray'),
            ),
            ListTile(
              leading: const Icon(Icons.undo, size: 20),
              title: const Text('Undo last drawing'),
              enabled: _drawings.isNotEmpty,
              onTap: () => Navigator.of(sheetContext).pop('undo'),
            ),
            if (_selectedDrawing != null)
              ListTile(
                leading: const Icon(Icons.delete_forever, size: 20),
                title: const Text('Delete selected drawing'),
                subtitle: const Text('Long-press a line to select it'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, size: 20),
              title: const Text('Clear drawings'),
              enabled: _drawings.isNotEmpty,
              onTap: () => Navigator.of(sheetContext).pop('clear'),
            ),
            ListTile(
              leading: const Icon(Icons.close, size: 20),
              title: const Text('Turn off drawing'),
              onTap: () => Navigator.of(sheetContext).pop('off'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'trend' || action == 'ray') {
      setState(() {
        _drawingTool =
            action == 'trend' ? DrawingTool.trend : DrawingTool.ray;
        _draftStart = null;
      });
      return;
    }
    if (action == 'delete') {
      final index = _selectedDrawing;
      if (index != null) _deleteDrawing(index);
      return;
    }
    if (action == 'undo' && _drawings.isNotEmpty) {
      _commitDrawings(_drawings.sublist(0, _drawings.length - 1));
      return;
    }
    if (action == 'clear') {
      setState(() => _draftStart = null);
      _commitDrawings(const []);
      return;
    }
    if (action == 'off') {
      setState(() {
        _drawingTool = DrawingTool.none;
        _draftStart = null;
      });
    }
  }

  /// A tap in drawing mode: rays are immediate, trend lines take two taps. The
  /// point is stored as a candle time so it survives a new window or session.
  void _onDraw(double index, double price) {
    if (_candles.isEmpty) return;
    final candle = _candles[index.round().clamp(0, _candles.length - 1)];
    final timeMs = candle.time.millisecondsSinceEpoch;
    if (_drawingTool == DrawingTool.ray) {
      _commitDrawings([..._drawings, ChartDrawing.ray(price: price)]);
      return;
    }
    if (_drawingTool != DrawingTool.trend) return;
    final start = _draftStart;
    if (start == null) {
      setState(() => _draftStart = DrawingDraft(timeMs: timeMs, price: price));
      return;
    }
    _commitDrawings([
      ..._drawings,
      ChartDrawing.trend(
        startMs: start.timeMs,
        startPrice: start.price,
        endMs: timeMs,
        endPrice: price,
      ),
    ]);
    setState(() => _draftStart = null);
  }

  void _toggleFullscreen() {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _openStyleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _styleSheet(_style, (next) {
              ChartStyle.current = next;
              // Persist in the background; the sheet repaints immediately. The
              // per-instrument layout is what reopening this symbol restores.
              unawaited(ChartStyle.save());
              unawaited(
                ChartStyle.saveLayout(widget.instrument.symbol, next),
              );
              if (!mounted) return;
              _style = next;
              setSheetState(() {});
              setState(() {});
            });
          },
        );
      },
    );
  }

  Widget _styleSheet(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    final label = TextStyle(
      color: AppColors.faint,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chart style',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => onChanged(ChartStyle.ink),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('THEME', style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in ChartStyle.presets)
                  _ThemeSwatch(
                    style: preset,
                    selected: preset.id == style.id &&
                        preset.bull == style.bull &&
                        preset.bear == style.bear,
                    onTap: () => onChanged(preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('CHART TYPE', style: label),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final type in ChartType.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _ChartTypeChip(
                        label: type.label,
                        selected: style.chartType == type,
                        onTap: () => onChanged(style.copyWith(chartType: type)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('STUDIES', style: label),
            for (final study in OverlayStudy.values) ...[
              _switchRow(
                studyLabel(study, period: style.periodFor(study)),
                style.studies.contains(study),
                (value) => onChanged(
                  style.copyWith(
                    studies: value
                        ? {...style.studies, study}
                        : ({...style.studies}..remove(study)),
                  ),
                ),
              ),
              if (style.studies.contains(study))
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _stepperRow(
                    'Period',
                    style.periodFor(study),
                    2,
                    400,
                    (value) => onChanged(
                      style.copyWith(
                        studyPeriods: {
                          ...style.studyPeriods,
                          study.name: value,
                        },
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text('PANES', style: label),
            _switchRow(
              'Volume',
              style.showVolume,
              (value) => onChanged(style.copyWith(showVolume: value)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final oscillator in Oscillator.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _ChartTypeChip(
                        label: oscillator.label,
                        selected: style.oscillator == oscillator,
                        onTap: () => onChanged(
                          style.copyWith(oscillator: oscillator),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (style.oscillator == Oscillator.rsi) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'RSI period',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final period in const [7, 14, 21])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _ChartTypeChip(
                        label: '$period',
                        selected: style.rsiPeriod == period,
                        onTap: () => onChanged(
                          style.copyWith(rsiPeriod: period),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (style.oscillator == Oscillator.macd) ...[
              const SizedBox(height: 4),
              _stepperRow(
                'Fast',
                style.macdFast,
                2,
                60,
                (value) => onChanged(style.copyWith(macdFast: value)),
              ),
              _stepperRow(
                'Slow',
                style.macdSlow,
                3,
                120,
                (value) => onChanged(style.copyWith(macdSlow: value)),
              ),
              _stepperRow(
                'Signal',
                style.macdSignal,
                2,
                60,
                (value) => onChanged(style.copyWith(macdSignal: value)),
              ),
            ],
            const SizedBox(height: 16),
            Text('CANDLES', style: label),
            _colorRow('Up', style.bull, (color) {
              onChanged(style.copyWith(bull: color));
            }),
            _colorRow('Down', style.bear, (color) {
              onChanged(style.copyWith(bear: color));
            }),
            const SizedBox(height: 16),
            Text('OVERLAYS', style: label),
            _switchRow(
              'Grid lines',
              style.showGrid,
              (value) => onChanged(style.copyWith(showGrid: value)),
            ),
            _switchRow(
              'Crosshair',
              style.showCrosshair,
              (value) => onChanged(style.copyWith(showCrosshair: value)),
            ),
            _switchRow(
              'Watermark',
              style.showWatermark,
              (value) => onChanged(style.copyWith(showWatermark: value)),
            ),
            _switchRow(
              'Log scale',
              style.logScale,
              (value) => onChanged(style.copyWith(logScale: value)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperRow(
    String title,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 16),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 26,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add, size: 16),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _colorRow(String title, Color current, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in ChartStyle.candlePalette)
                  _ColorDot(
                    color: color,
                    selected: color == current,
                    onTap: () => onPick(color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _chartError({bool expand = false}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart, size: 26, color: AppColors.faint),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    if (expand) return Center(child: content);
    return SizedBox(height: _TradingChartPainter.height, child: content);
  }

  Widget _header(Instrument instrument) {
    final last = _lastVisible?.close;
    final change = _changePercent;
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instrument.symbol,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      instrument.name,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    last == null ? '—' : chartPrice(last, instrument),
                    style: tabular.copyWith(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (change != null) ...[
                    const SizedBox(height: 4),
                    Pill(
                      text:
                          '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                      tone: change >= 0 ? Tone.positive : Tone.negative,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Pill(
                text: widget.direction.toUpperCase(),
                tone: _isBuy ? Tone.positive : Tone.negative,
              ),
              const SizedBox(width: 6),
              Pill(
                text: 'LIVE',
                tone: Tone.positive,
              ),
              const Spacer(),
              if (_updated != null)
                Text(
                  'Updated ${DateFormat('HH:mm:ss').format(_updated!)}',
                  style: tabular.copyWith(
                    color: AppColors.faint,
                    fontSize: 9.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String get _windowLabel {
    final from = _windowFrom;
    final to = _windowTo;
    if (from == null || to == null) return 'Live · newest candles';
    return '${_stamp(from)} → ${_stamp(to)}';
  }

  Future<void> _openTimeFrameSheet() async {
    final now = DateTime.now();
    final choice = await showChartTimeFrameSheet(
      context: context,
      from: _windowFrom ?? now.subtract(const Duration(days: 1)),
      to: _windowTo ?? now,
      interval: _interval,
    );
    if (choice == null || !mounted) return;
    if (choice.isLive) {
      _setLive();
      return;
    }
    await _applyWindow(choice.from!, choice.to!, choice.interval!);
  }

  Widget _timeFrame({bool overlay = false}) {
    // On the fullscreen canvas the control sits on the chart itself, so it takes
    // the chart's palette instead of the app's surface colour.
    final surface = overlay ? _style.background : AppColors.surface;
    final border = overlay ? _style.axis : AppColors.border;
    final accent = overlay ? _style.text : AppColors.primaryLight;
    final idleInk = overlay ? _style.muted : AppColors.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'TIME FRAME',
              style: TextStyle(
                color: idleInk,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            if (_customWindow)
              GestureDetector(
                onTap: _setLive,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'Back to live',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _openTimeFrameSheet,
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 15, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _windowLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tabular.copyWith(
                          color: overlay ? _style.text : AppColors.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${_interval.detail} · tap to change',
                        style: TextStyle(
                          color: idleInk,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: idleInk),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chartFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 12,
            color: AppColors.faint,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Drag to scroll · pinch to zoom · tap to set ${_labelFor(_active)} · long-press a line to move it',
              style: TextStyle(
                color: AppColors.faint,
                fontSize: 9.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(_Marker marker) {
    switch (marker) {
      case _Marker.entry:
        return 'entry';
      case _Marker.stop:
        return 'stop';
      case _Marker.take:
        return 'target';
      case _Marker.exit:
        return 'exit';
    }
  }

  Widget _disclaimer() {
    return FlatCard(
      padding: const EdgeInsets.all(12),
      borderColor: AppColors.success.withAlpha(70),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Live OANDA CFD quotes, refreshed every minute. The broker price still decides the fill — confirm it before you act.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelsCard() {
    final instrument = widget.instrument;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Levels',
            subtitle:
                'Tap a row, then tap the chart where that level sat. Hold a line to move it — for entry and exit the time moves too. Nothing reaches the form until you confirm.',
          ),
          const SizedBox(height: 8),
          _LevelRow(
            label: 'Entry',
            price: _entry,
            time: _entryTime,
            instrument: instrument,
            color: AppColors.primary,
            active: _active == _Marker.entry,
            onSelect: () => setState(() => _active = _Marker.entry),
            onClear: _entry == null ? null : () => _clear(_Marker.entry),
          ),
          const SizedBox(height: 6),
          _LevelRow(
            label: 'Stop loss',
            price: _stop,
            instrument: instrument,
            color: AppColors.danger,
            active: _active == _Marker.stop,
            onSelect: () => setState(() => _active = _Marker.stop),
            onClear: _stop == null ? null : () => _clear(_Marker.stop),
          ),
          const SizedBox(height: 6),
          _LevelRow(
            label: 'Take profit',
            price: _take,
            instrument: instrument,
            color: AppColors.success,
            active: _active == _Marker.take,
            onSelect: () => setState(() => _active = _Marker.take),
            onClear: _take == null ? null : () => _clear(_Marker.take),
          ),
          const SizedBox(height: 6),
          _LevelRow(
            label: 'Exit',
            price: _exit,
            time: _exitTime,
            instrument: instrument,
            color: AppColors.muted,
            active: _active == _Marker.exit,
            onSelect: () => setState(() => _active = _Marker.exit),
            onClear: _exit == null ? null : () => _clear(_Marker.exit),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final hasLevels =
        _entry != null || _exit != null || _stop != null || _take != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasLevels)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  'Adjust the points on the chart, then confirm — nothing is written to the form until you do.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ),
            ElevatedButton(
              onPressed: hasLevels && !_timeInvalid ? _confirmLevels : null,
              child: const Text('Review and confirm levels'),
            ),
          ],
        ),
      ),
    );
  }

  /// The last step: the levels only reach the trade form after this sheet is
  /// confirmed, so a stray tap on the chart cannot overwrite a typed price.
  Future<void> _confirmLevels() async {
    final selection = ChartSelection(
      entry: _entry,
      exit: _exit,
      stop: _stop,
      take: _take,
      entryTime: _entryTime,
      exitTime: _exitTime,
    );
    if (selection.isEmpty || _timeInvalid) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.checklist, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Confirm the levels',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'These values are written into the trade form once you confirm. Keep adjusting if a point is off.',
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              _confirmRow(
                'Entry',
                selection.entry,
                selection.entryTime,
                AppColors.primary,
              ),
              _confirmRow('Stop loss', selection.stop, null, AppColors.danger),
              _confirmRow(
                'Take profit',
                selection.take,
                null,
                AppColors.success,
              ),
              _confirmRow(
                'Exit',
                selection.exit,
                selection.exitTime,
                AppColors.muted,
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Confirm and use'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Keep adjusting'),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    Navigator.pop(context, selection);
  }

  Widget _confirmRow(
    String label,
    double? price,
    DateTime? time,
    Color color,
  ) {
    final instrument = widget.instrument;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
          Text(
            price == null ? '—' : chartPrice(price, instrument),
            style: tabular.copyWith(
              color: price == null ? AppColors.faint : AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (time != null) ...[
            const SizedBox(width: 8),
            Text(
              DateFormat('d MMM HH:mm').format(time),
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Owns the interactive canvas. Keeping the viewport, crosshair and drag state
/// here means a finger move repaints only the chart, not the cards around it.
class _ChartCanvas extends StatefulWidget {
  const _ChartCanvas({
    required this.candles,
    required this.interval,
    required this.decimals,
    required this.symbol,
    required this.style,
    required this.active,
    required this.entry,
    required this.stop,
    required this.take,
    required this.exit,
    required this.entryTime,
    required this.exitTime,
    required this.onSelect,
    required this.onPin,
    required this.onLevelMoved,
    required this.drawTool,
    required this.drawings,
    required this.draftStart,
    required this.selectedDrawing,
    required this.onDrawingSelected,
    required this.onDrawingMoved,
    required this.onDrawingMoveEnd,
    required this.onDraw,
    this.height,
  });

  final List<Candle> candles;
  final ChartInterval interval;
  final int decimals;
  final String symbol;
  final ChartStyle style;

  /// Fixed canvas height, or null to fill the space the parent offers (the
  /// fullscreen layout).
  final double? height;
  final _Marker active;
  final double? entry;
  final double? stop;
  final double? take;
  final double? exit;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final ValueChanged<_Marker> onSelect;
  final void Function(_Marker marker, double price, DateTime time) onPin;
  final void Function(_Marker marker, double price, DateTime? time) onLevelMoved;
  final DrawingTool drawTool;
  final List<ChartDrawing> drawings;
  final DrawingDraft? draftStart;
  final int? selectedDrawing;
  final ValueChanged<int?> onDrawingSelected;
  final void Function(int index, ChartDrawing drawing) onDrawingMoved;
  final VoidCallback onDrawingMoveEnd;
  final void Function(double index, double price) onDraw;

  @override
  State<_ChartCanvas> createState() => _ChartCanvasState();
}

class _ChartCanvasState extends State<_ChartCanvas> {
  final _view = ChartViewport();

  double? _entry;
  double? _stop;
  double? _take;
  double? _exit;
  DateTime? _entryTime;
  DateTime? _exitTime;

  Size _size = Size.zero;
  Offset? _crosshair;

  /// Study series aligned with the candles, rebuilt when either changes.
  Map<OverlayStudy, List<double?>> _studies = const {};
  _Marker? _dragging;
  int? _drawingIndex;
  ChartDrawing? _drawingOriginal;
  Offset _dragOrigin = Offset.zero;
  double _baseSpan = 0;
  double _baseStart = 0;

  @override
  void initState() {
    super.initState();
    _syncLevels();
    _view.fit(widget.candles.length);
    _rebuildStudies();
  }

  @override
  void didUpdateWidget(covariant _ChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles) ||
        oldWidget.interval != widget.interval) {
      if (oldWidget.candles.isEmpty || oldWidget.interval != widget.interval) {
        _view.fit(widget.candles.length);
      } else {
        _view.clampTo(widget.candles.length);
      }
    }
    if (!identical(oldWidget.candles, widget.candles) ||
        !setEquals(oldWidget.style.studies, widget.style.studies) ||
        !mapEquals(
          oldWidget.style.studyPeriods,
          widget.style.studyPeriods,
        )) {
      _rebuildStudies();
    }
    if (_dragging == null) _syncLevels();
  }

  void _rebuildStudies() {
    final studies = widget.style.studies;
    if (studies.isEmpty || widget.candles.isEmpty) {
      _studies = const {};
      return;
    }
    final closes = [for (final candle in widget.candles) candle.close];
    _studies = {
      for (final study in studies)
        study: studySeries(
          study,
          closes,
          period: widget.style.periodFor(study),
        ),
    };
  }

  void _syncLevels() {
    _entry = widget.entry;
    _stop = widget.stop;
    _take = widget.take;
    _exit = widget.exit;
    _entryTime = widget.entryTime;
    _exitTime = widget.exitTime;
  }

  ({double min, double max}) _bounds() {
    if (widget.candles.isEmpty) return (min: 0, max: 1);
    final visible = _view.visible(widget.candles.length);
    final values = <double>[];
    for (var i = visible.first; i < visible.last; i++) {
      values
        ..add(widget.candles[i].high)
        ..add(widget.candles[i].low);
    }
    // A moving average can sit outside the candles' range, so the axis has to
    // widen for it the way a charting platform does.
    for (final series in _studies.values) {
      for (var i = visible.first; i < visible.last && i < series.length; i++) {
        final value = series[i];
        if (value != null) values.add(value);
      }
    }
    if (values.isEmpty) {
      for (final candle in widget.candles) {
        values
          ..add(candle.high)
          ..add(candle.low);
      }
    }
    var min = values.reduce(math.min);
    var max = values.reduce(math.max);
    if (max - min < 1e-9) {
      min -= 1;
      max += 1;
    }
    final pad = (max - min) * 0.06;
    return (min: min - pad, max: max + pad);
  }

  double _priceFor(Offset local) {
    final bounds = _bounds();
    final panes =
        _TradingChartPainter.paneLayout(_size.height, widget.style);
    if (panes.priceH <= 0) return bounds.max;
    final ratio = ((local.dy - panes.priceTop) / panes.priceH)
        .clamp(0.0, 1.0)
        .toDouble();
    return priceForRatio(
      ratio: ratio,
      min: bounds.min,
      max: bounds.max,
      logScale: widget.style.logScale,
    );
  }

  /// Candle time under [local]'s x. Null when the canvas has no width yet.
  DateTime? _timeFor(Offset local) {
    if (widget.candles.isEmpty) return null;
    final plotW = _size.width - _TradingChartPainter.axisWidth;
    if (plotW <= 0) return null;
    final ratio = (local.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, widget.candles.length);
    return widget.candles[index].time.toLocal();
  }

  double _yFor(double price) {
    final bounds = _bounds();
    final panes =
        _TradingChartPainter.paneLayout(_size.height, widget.style);
    return panes.priceTop +
        ratioForPrice(
          price: price,
          min: bounds.min,
          max: bounds.max,
          logScale: widget.style.logScale,
        ) *
            panes.priceH;
  }

  void _setDraft(_Marker marker, double price) {
    switch (marker) {
      case _Marker.entry:
        _entry = price;
        break;
      case _Marker.stop:
        _stop = price;
        break;
      case _Marker.take:
        _take = price;
        break;
      case _Marker.exit:
        _exit = price;
        break;
    }
  }

  void _tap(Offset local) {
    if (widget.candles.isEmpty) return;
    final plotW = _size.width - _TradingChartPainter.axisWidth;
    if (plotW <= 0 || local.dx > plotW) return;
    if (widget.drawTool == DrawingTool.none &&
        widget.selectedDrawing != null) {
      widget.onDrawingSelected(null);
    }
    if (widget.drawTool != DrawingTool.none) {
      final panes =
          _TradingChartPainter.paneLayout(_size.height, widget.style);
      if (local.dy < panes.priceTop ||
          local.dy > panes.priceTop + panes.priceH) {
        return;
      }
      final ratio = (local.dx / plotW).clamp(0.0, 1.0).toDouble();
      widget.onDraw(_view.start + ratio * _view.span, _priceFor(local));
      return;
    }
    final ratio = (local.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, widget.candles.length);
    final time = widget.candles[index].time.toLocal();
    final price = _priceFor(local);
    setState(() {
      _setDraft(widget.active, price);
      if (widget.active == _Marker.entry) _entryTime = time;
      if (widget.active == _Marker.exit) _exitTime = time;
    });
    widget.onPin(widget.active, price, time);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseSpan = _view.span;
    _baseStart = _view.start;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.candles.length < 2) return;
    final plotW = _size.width - _TradingChartPainter.axisWidth;
    if (plotW <= 0) return;
    final ratio =
        (details.localFocalPoint.dx / plotW).clamp(0.0, 1.0).toDouble();
    setState(() {
      if (details.pointerCount >= 2) {
        _view.zoomAround(
          scale: details.scale,
          anchorRatio: ratio,
          count: widget.candles.length,
          baseSpan: _baseSpan,
          baseStart: _baseStart,
        );
      } else {
        _view.pan(-details.focalPointDelta.dx / plotW * _view.span);
        _view.clampTo(widget.candles.length);
      }
      _crosshair = details.localFocalPoint;
    });
  }

  _Marker? _nearestLevel(Offset local) {
    double? bestDistance;
    _Marker? best;
    void check(_Marker marker, double? price) {
      if (price == null) return;
      final dy = (_yFor(price) - local.dy).abs();
      if (dy <= 22 && (bestDistance == null || dy < bestDistance!)) {
        bestDistance = dy;
        best = marker;
      }
    }

    check(_Marker.entry, _entry);
    check(_Marker.stop, _stop);
    check(_Marker.take, _take);
    check(_Marker.exit, _exit);
    return best;
  }

  /// Nearest candle index for an epoch-millisecond time, or null when the
  /// drawing sits outside the loaded series.
  double? _indexForTime(int ms) {
    final candles = widget.candles;
    if (candles.isEmpty) return null;
    final first = candles.first.time.millisecondsSinceEpoch;
    final last = candles.last.time.millisecondsSinceEpoch;
    if (ms < first || ms > last) return null;
    var low = 0;
    var high = candles.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (candles[mid].time.millisecondsSinceEpoch < ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low.toDouble();
  }

  double _xForIndex(double index, double plotW) =>
      ((index + 0.5 - _view.start) / _view.span) * plotW;

  double? _drawingDistance(ChartDrawing drawing, Offset local, double plotW) {
    if (drawing.kind == DrawingKind.ray) {
      final price = drawing.price;
      if (price == null) return null;
      return (_yFor(price) - local.dy).abs();
    }
    final start = _indexForTime(drawing.startMs);
    final end = _indexForTime(drawing.endMs);
    if (start == null || end == null) return null;
    return _distanceToSegment(
      local,
      Offset(_xForIndex(start, plotW), _yFor(drawing.startPrice)),
      Offset(_xForIndex(end, plotW), _yFor(drawing.endPrice)),
    );
  }

  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-9) return (point - a).distance;
    final t = (((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) /
            lengthSquared)
        .clamp(0.0, 1.0);
    return (point - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
  }

  int? _nearestDrawing(Offset local) {
    final plotW = _size.width - _TradingChartPainter.axisWidth;
    if (plotW <= 0) return null;
    int? best;
    var bestDistance = 14.0;
    for (var i = 0; i < widget.drawings.length; i++) {
      final distance = _drawingDistance(widget.drawings[i], local, plotW);
      if (distance != null && distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// Moves a drawing with the finger: prices follow vertically, and a trend
  /// line's times follow horizontally so its slope stays put.
  ChartDrawing _movedDrawing(ChartDrawing original, Offset local) {
    final priceDelta = _priceFor(_dragOrigin) - _priceFor(local);
    if (original.kind == DrawingKind.ray) {
      return ChartDrawing.ray(price: (original.price ?? 0) + priceDelta);
    }
    final plotW = _size.width - _TradingChartPainter.axisWidth;
    final shift = plotW <= 0
        ? 0.0
        : (local.dx - _dragOrigin.dx) / plotW * _view.span;
    final candles = widget.candles;
    int shiftTime(int ms) {
      final index = _indexForTime(ms);
      if (index == null) return ms;
      final moved = (index + shift).round().clamp(0, candles.length - 1);
      return candles[moved].time.millisecondsSinceEpoch;
    }

    return ChartDrawing.trend(
      startMs: shiftTime(original.startMs),
      startPrice: original.startPrice + priceDelta,
      endMs: shiftTime(original.endMs),
      endPrice: original.endPrice + priceDelta,
    );
  }

  void _startDrag(Offset local) {
    final drawing = _nearestDrawing(local);
    if (drawing != null) {
      setState(() {
        _crosshair = null;
        _drawingIndex = drawing;
        _drawingOriginal = widget.drawings[drawing];
        _dragOrigin = local;
      });
      widget.onDrawingSelected(drawing);
      return;
    }
    final marker = _nearestLevel(local);
    setState(() {
      _crosshair = local;
      if (marker != null) {
        _dragging = marker;
      }
    });
    if (marker != null) {
      widget.onSelect(marker);
    } else {
      widget.onDrawingSelected(null);
    }
  }

  void _updateDrag(Offset local) {
    final drawing = _drawingOriginal;
    final index = _drawingIndex;
    if (drawing != null && index != null) {
      setState(() => _crosshair = null);
      widget.onDrawingMoved(index, _movedDrawing(drawing, local));
      return;
    }
    final marker = _dragging;
    if (marker == null) {
      setState(() => _crosshair = local);
      return;
    }
    setState(() {
      _setDraft(marker, _priceFor(local));
      // Entry and exit are points, not just prices: the time follows the drag.
      final time = _timeFor(local);
      if (time != null) {
        if (marker == _Marker.entry) _entryTime = time;
        if (marker == _Marker.exit) _exitTime = time;
      }
      _crosshair = local;
    });
  }

  void _endDrag(Offset local) {
    if (_drawingIndex != null) {
      setState(() {
        _drawingIndex = null;
        _drawingOriginal = null;
      });
      widget.onDrawingMoveEnd();
      return;
    }
    final marker = _dragging;
    setState(() {
      _dragging = null;
      _crosshair = null;
    });
    if (marker == null) return;
    final price = switch (marker) {
      _Marker.entry => _entry,
      _Marker.stop => _stop,
      _Marker.take => _take,
      _Marker.exit => _exit,
    };
    if (price == null) return;
    // Only the point markers carry a time; the parent ignores it for stop/take.
    final time = switch (marker) {
      _Marker.entry => _entryTime,
      _Marker.exit => _exitTime,
      _ => null,
    };
    widget.onLevelMoved(marker, price, time ?? _timeFor(local));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      if (widget.height == null) {
        return SizedBox.expand(
          child: ColoredBox(color: widget.style.background),
        );
      }
      return const SizedBox(height: _TradingChartPainter.height);
    }
    final bounds = _bounds();
    final fixedHeight = widget.height;
    if (fixedHeight != null) return _sized(fixedHeight, bounds);
    return LayoutBuilder(
      builder: (context, constraints) => _sized(constraints.maxHeight, bounds),
    );
  }

  Widget _sized(double height, ({double min, double max}) bounds) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = Size(constraints.maxWidth, height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _tap(details.localPosition),
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: (_) => setState(() => _crosshair = null),
            onLongPressStart: (details) => _startDrag(details.localPosition),
            onLongPressMoveUpdate: (details) =>
                _updateDrag(details.localPosition),
            onLongPressEnd: (details) => _endDrag(details.localPosition),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TradingChartPainter(
                      candles: widget.candles,
                      start: _view.start,
                      span: _view.span,
                      minPrice: bounds.min,
                      maxPrice: bounds.max,
                      entry: _entry,
                      exit: _exit,
                      stop: _stop,
                      take: _take,
                      entryTime: _entryTime,
                      exitTime: _exitTime,
                      crosshair: _crosshair,
                      dragging: _dragging,
                      decimals: widget.decimals,
                      interval: widget.interval,
                      chartType: widget.style.chartType,
                      studies: _studies,
                      drawings: widget.drawings,
                      draftStart: widget.draftStart,
                      selectedDrawing: widget.selectedDrawing,
                      style: widget.style,
                      symbol: widget.symbol,
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  right: _TradingChartPainter.axisWidth + 6,
                  child: IgnorePointer(child: _readout()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _readout() {
    final plotW = _size.width - _TradingChartPainter.axisWidth;
    final ratio = _crosshair == null || plotW <= 0
        ? 1.0
        : (_crosshair!.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, widget.candles.length);
    final candle = widget.candles[index];
    final color = candle.isUp ? widget.style.bull : widget.style.bear;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: widget.style.background.withAlpha(190),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '· ${widget.interval.key}  ',
              style: TextStyle(
                color: widget.style.muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: 'O ${candle.open.toStringAsFixed(widget.decimals)}  '
                  'H ${candle.high.toStringAsFixed(widget.decimals)}  '
                  'L ${candle.low.toStringAsFixed(widget.decimals)}  '
                  'C ${candle.close.toStringAsFixed(widget.decimals)}',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final entry in _studies.entries)
              if (entry.value.length > index && entry.value[index] != null)
                TextSpan(
                  text:
                      '   ${studyLabel(entry.key, period: widget.style.periodFor(entry.key))} ${entry.value[index]!.toStringAsFixed(widget.decimals)}',
                  style: TextStyle(
                    color: entry.key.color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// One option in the chart-type row.
class _ChartTypeChip extends StatelessWidget {
  const _ChartTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withAlpha(30) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primaryLight : AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.label,
    required this.price,
    required this.instrument,
    required this.color,
    required this.active,
    required this.onSelect,
    this.time,
    this.onClear,
  });

  final String label;
  final double? price;
  final DateTime? time;
  final Instrument instrument;
  final Color color;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(18) : AppColors.surfaceAlt,
          border: Border.all(
            color: active ? color.withAlpha(120) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 74,
              child: Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.text : AppColors.muted,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                price == null
                    ? 'Tap the chart'
                    : chartPrice(price!, instrument),
                style: tabular.copyWith(
                  color: price == null ? AppColors.faint : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (time != null)
              Text(
                DateFormat('d MMM HH:mm').format(time!),
                style: tabular.copyWith(color: AppColors.faint, fontSize: 10),
              ),
            if (onClear != null)
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.only(left: 8, top: 2, bottom: 2),
                  child: Icon(Icons.close, size: 13, color: AppColors.faint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 13,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.primaryLight,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Candles, price/time axes, crosshair and the draggable level lines.
class _TradingChartPainter extends CustomPainter {
  _TradingChartPainter({
    required this.candles,
    required this.start,
    required this.span,
    required this.minPrice,
    required this.maxPrice,
    required this.entry,
    required this.exit,
    required this.stop,
    required this.take,
    required this.entryTime,
    required this.exitTime,
    required this.crosshair,
    required this.dragging,
    required this.decimals,
    required this.interval,
    required this.chartType,
    required this.studies,
    required this.drawings,
    required this.draftStart,
    required this.style,
    required this.symbol,
    required this.selectedDrawing,
  });

  static const double height = 380;
  static const double axisWidth = 58;
  static const double topPad = 10;
  static const double bottomPad = 20;
  static const double paneGap = 8;

  /// Vertical layout of the price pane plus the optional volume and oscillator
  /// panes. Shares always add up to 1, so the panes fill the canvas exactly.
  static ({
    double priceTop,
    double priceH,
    double volumeTop,
    double volumeH,
    double oscTop,
    double oscH,
  }) paneLayout(double height, ChartStyle style) {
    final hasVolume = style.showVolume;
    final hasOscillator = style.oscillator != Oscillator.none;
    final total = height - topPad - bottomPad;
    final gaps = (hasVolume ? paneGap : 0.0) + (hasOscillator ? paneGap : 0.0);
    final usable = math.max(0.0, total - gaps);
    var priceShare = 1.0;
    if (hasVolume && hasOscillator) {
      priceShare = 0.58;
    } else if (hasVolume || hasOscillator) {
      priceShare = 0.76;
    }
    final priceH = usable * priceShare;
    var volumeTop = 0.0;
    var volumeH = 0.0;
    var oscTop = 0.0;
    var oscH = 0.0;
    var cursor = topPad + priceH;
    if (hasVolume) {
      volumeTop = cursor + paneGap;
      volumeH = usable * (hasOscillator ? 0.16 : 0.24);
      cursor = volumeTop + volumeH;
    }
    if (hasOscillator) {
      oscTop = cursor + paneGap;
      oscH = usable * 0.26;
    }
    return (
      priceTop: topPad,
      priceH: priceH,
      volumeTop: volumeTop,
      volumeH: volumeH,
      oscTop: oscTop,
      oscH: oscH,
    );
  }

  final List<Candle> candles;
  final double start;
  final double span;
  final double minPrice;
  final double maxPrice;
  final double? entry;
  final double? exit;
  final double? stop;
  final double? take;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final Offset? crosshair;
  final _Marker? dragging;
  final int decimals;
  final ChartInterval interval;
  final ChartType chartType;
  final Map<OverlayStudy, List<double?>> studies;
  final List<ChartDrawing> drawings;
  final DrawingDraft? draftStart;
  final ChartStyle style;
  final String symbol;
  final int? selectedDrawing;

  /// Nearest candle x for an epoch-millisecond time, or null when the drawing
  /// sits outside the loaded series (then it is simply not drawn).
  double? _xForTime(int ms, double plotW) {
    if (candles.isEmpty) return null;
    final first = candles.first.time.millisecondsSinceEpoch;
    final last = candles.last.time.millisecondsSinceEpoch;
    if (ms < first || ms > last) return null;
    var low = 0;
    var high = candles.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (candles[mid].time.millisecondsSinceEpoch < ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return ((low + 0.5 - start) / span) * plotW;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.background);
    final plotW = size.width - axisWidth;
    final panes = paneLayout(size.height, style);
    final plotH = panes.priceH;
    if (candles.isEmpty || plotW <= 0 || plotH <= 0) return;

    if (style.showWatermark) _watermark(canvas, plotW, plotH);

    double y(double price) =>
        panes.priceTop +
        ratioForPrice(
          price: price,
          min: minPrice,
          max: maxPrice,
          logScale: style.logScale,
        ) *
            plotH;
    double x(double index) => ((index + 0.5 - start) / span) * plotW;

    final grid = Paint()
      ..color = style.grid
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final gy = topPad + plotH * i / 4;
      if (style.showGrid) {
        canvas.drawLine(Offset(0, gy), Offset(plotW, gy), grid);
      }
      final price = priceForRatio(
        ratio: i / 4,
        min: minPrice,
        max: maxPrice,
        logScale: style.logScale,
      );
      _label(
        canvas,
        price.toStringAsFixed(decimals),
        Offset(plotW + 6, gy - 5),
        color: style.muted,
        size: 8.5,
      );
    }
    final step = math.max(1, (span / 5).round());
    final firstGrid = (start / step).floor() * step;
    for (var i = firstGrid; i <= start + span; i += step) {
      if (i < 0 || i >= candles.length) continue;
      final gx = x(i.toDouble());
      if (gx < 0 || gx > plotW) continue;
      if (style.showGrid) {
        canvas.drawLine(Offset(gx, topPad), Offset(gx, topPad + plotH), grid);
      }
    }

    final slot = plotW / span;
    final bodyWidth = math.max(1.2, slot * 0.66);
    if (chartType == ChartType.candles) {
      for (var i = 0; i < candles.length; i++) {
        final candle = candles[i];
        final cx = x(i.toDouble());
        if (cx < -slot || cx > plotW + slot) continue;
        final color = candle.isUp ? style.bull : style.bear;
        canvas.drawLine(
          Offset(cx, y(candle.high)),
          Offset(cx, y(candle.low)),
          Paint()
            ..color = color
            ..strokeWidth = 1,
        );
        final openY = y(candle.open);
        final closeY = y(candle.close);
        final body = Rect.fromLTRB(
          cx - bodyWidth / 2,
          math.min(openY, closeY),
          cx + bodyWidth / 2,
          math.max(openY, closeY) + 0.8,
        );
        canvas.drawRect(body, Paint()..color = color.withAlpha(210));
      }
    } else {
      final line = Path();
      var started = false;
      for (var i = 0; i < candles.length; i++) {
        final cx = x(i.toDouble());
        if (cx < -slot || cx > plotW + slot) continue;
        final cy = y(candles[i].close);
        if (!started) {
          line.moveTo(cx, cy);
          started = true;
        } else {
          line.lineTo(cx, cy);
        }
      }
      if (started) {
        if (chartType == ChartType.area) {
          final bounds = line.getBounds();
          final fill = Path.from(line)
            ..lineTo(bounds.right, topPad + plotH)
            ..lineTo(bounds.left, topPad + plotH)
            ..close();
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [style.bull.withAlpha(70), style.bull.withAlpha(0)],
              ).createShader(Rect.fromLTWH(0, topPad, plotW, plotH)),
          );
        }
        canvas.drawPath(
          line,
          Paint()
            ..color = style.text.withAlpha(230)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }

    // Moving averages sit on top of whichever series is drawn.
    for (final entry in studies.entries) {
      final paint = Paint()
        ..color = entry.key.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      final series = entry.value;
      Path? run;
      for (var i = 0; i < series.length && i < candles.length; i++) {
        final value = series[i];
        final px = x(i.toDouble());
        if (value == null || px < -slot || px > plotW + slot) {
          if (run != null) {
            canvas.drawPath(run, paint);
            run = null;
          }
          continue;
        }
        final py = y(value);
        if (run == null) {
          run = Path()..moveTo(px, py);
        } else {
          run.lineTo(px, py);
        }
      }
      if (run != null) canvas.drawPath(run, paint);
    }

    // Volume pane: bars scaled to the busiest visible bar.
    if (panes.volumeH > 6) {
      final bottom = panes.volumeTop + panes.volumeH;
      final firstVisible = start.floor().clamp(0, candles.length - 1);
      final lastVisible =
          (start + span).ceil().clamp(firstVisible + 1, candles.length);
      var maxVolume = 0.0;
      for (var i = firstVisible; i < lastVisible; i++) {
        maxVolume = math.max(maxVolume, candles[i].volume);
      }
      canvas.drawLine(
        Offset(0, panes.volumeTop),
        Offset(plotW, panes.volumeTop),
        Paint()
          ..color = style.axis
          ..strokeWidth = 0.6,
      );
      _label(
        canvas,
        'VOL',
        Offset(4, panes.volumeTop + 2),
        color: style.muted,
        size: 8,
      );
      if (maxVolume > 0) {
        for (var i = 0; i < candles.length; i++) {
          final cx = x(i.toDouble());
          if (cx < -slot || cx > plotW + slot) continue;
          final height = candles[i].volume / maxVolume * (panes.volumeH - 12);
          if (height <= 0) continue;
          final color = candles[i].isUp ? style.bull : style.bear;
          canvas.drawRect(
            Rect.fromLTRB(
              cx - bodyWidth / 2,
              bottom - height,
              cx + bodyWidth / 2,
              bottom,
            ),
            Paint()..color = color.withAlpha(110),
          );
        }
      }
    }

    // Oscillator pane: RSI with its 30/70 guides, or MACD with histogram.
    if (panes.oscH > 6) {
      final paneTop = panes.oscTop;
      final paneBottom = paneTop + panes.oscH;
      final closes = [for (final candle in candles) candle.close];
      canvas.drawLine(
        Offset(0, paneTop),
        Offset(plotW, paneTop),
        Paint()
          ..color = style.axis
          ..strokeWidth = 0.6,
      );
      if (style.oscillator == Oscillator.rsi) {
        final series = rsi(closes, period: style.rsiPeriod.clamp(2, 100));
        double oy(double value) =>
            paneBottom - (value.clamp(0, 100) / 100) * (panes.oscH - 10) - 4;
        for (final level in const [30.0, 70.0]) {
          final gy = oy(level);
          _dashed(canvas, Offset(0, gy), Offset(plotW, gy), style.grid);
          _label(
            canvas,
            level.toStringAsFixed(0),
            Offset(plotW + 6, gy - 5),
            color: style.muted,
            size: 8,
          );
        }
        _label(
          canvas,
          'RSI ${style.rsiPeriod}',
          Offset(4, paneTop + 2),
          color: style.muted,
          size: 8,
        );
        final paint = Paint()
          ..color = const Color(0xFF9C8CFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        Path? run;
        for (var i = 0; i < series.length; i++) {
          final value = series[i];
          final px = i < candles.length ? x(i.toDouble()) : 0.0;
          if (value == null || px < -slot || px > plotW + slot) {
            if (run != null) {
              canvas.drawPath(run, paint);
              run = null;
            }
            continue;
          }
          final py = oy(value);
          if (run == null) {
            run = Path()..moveTo(px, py);
          } else {
            run.lineTo(px, py);
          }
        }
        if (run != null) canvas.drawPath(run, paint);
      } else if (style.oscillator == Oscillator.macd) {
        final points = macd(
          closes,
          fast: style.macdFast.clamp(2, 100),
          slow: style.macdSlow.clamp(3, 200),
          signal: style.macdSignal.clamp(2, 100),
        );
        var maxAbs = 1e-9;
        for (final point in points) {
          if (point == null) continue;
          maxAbs = math.max(maxAbs, point.macd.abs());
          maxAbs = math.max(maxAbs, point.signal.abs());
          maxAbs = math.max(maxAbs, point.histogram.abs());
        }
        double oy(double value) =>
            paneBottom - (value + maxAbs) / (2 * maxAbs) * (panes.oscH - 10) - 4;
        _dashed(canvas, Offset(0, oy(0)), Offset(plotW, oy(0)), style.grid);
        _label(
          canvas,
          'MACD ${style.macdFast},${style.macdSlow},${style.macdSignal}',
          Offset(4, paneTop + 2),
          color: style.muted,
          size: 8,
        );
        for (var i = 0; i < points.length; i++) {
          final point = points[i];
          if (point == null) continue;
          final cx = x(i.toDouble());
          if (cx < -slot || cx > plotW + slot) continue;
          final zero = oy(0);
          final value = oy(point.histogram);
          canvas.drawRect(
            Rect.fromLTRB(
              cx - bodyWidth / 2,
              math.min(zero, value),
              cx + bodyWidth / 2,
              math.max(zero, value),
            ),
            Paint()
              ..color = (point.histogram >= 0 ? style.bull : style.bear)
                  .withAlpha(120),
          );
        }
        void line(Paint paint, double Function(MacdPoint) pick) {
          Path? run;
          for (var i = 0; i < points.length; i++) {
            final point = points[i];
            final px = x(i.toDouble());
            if (point == null || px < -slot || px > plotW + slot) {
              if (run != null) {
                canvas.drawPath(run, paint);
                run = null;
              }
              continue;
            }
            final py = oy(pick(point));
            if (run == null) {
              run = Path()..moveTo(px, py);
            } else {
              run.lineTo(px, py);
            }
          }
          if (run != null) canvas.drawPath(run, paint);
        }

        line(
          Paint()
            ..color = const Color(0xFF4C9AFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
          (point) => point.macd,
        );
        line(
          Paint()
            ..color = const Color(0xFFFF8A5C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
          (point) => point.signal,
        );
      }
    }

    // Trader drawings, then the half-finished trend line if one is in progress.
    for (var d = 0; d < drawings.length; d++) {
      final drawing = drawings[d];
      final selected = d == selectedDrawing;
      final paint = Paint()
        ..color = drawingColor
        ..strokeWidth = selected ? 2.4 : 1.3
        ..style = PaintingStyle.stroke;
      if (drawing.kind == DrawingKind.ray) {
        final price = drawing.price;
        if (price == null) continue;
        final ly = y(price);
        if (ly < panes.priceTop || ly > panes.priceTop + plotH) continue;
        canvas.drawLine(Offset(0, ly), Offset(plotW, ly), paint);
        if (selected) {
          canvas.drawCircle(
            Offset(plotW / 2, ly),
            4,
            Paint()..color = drawingColor,
          );
        }
      } else {
        final x1 = _xForTime(drawing.startMs, plotW);
        final x2 = _xForTime(drawing.endMs, plotW);
        if (x1 == null || x2 == null) continue;
        final p1 = Offset(x1, y(drawing.startPrice));
        final p2 = Offset(x2, y(drawing.endPrice));
        canvas.drawLine(p1, p2, paint);
        final handle = selected ? 4.0 : 2.5;
        canvas.drawCircle(p1, handle, Paint()..color = drawingColor);
        canvas.drawCircle(p2, handle, Paint()..color = drawingColor);
      }
    }
    final draft = draftStart;
    final draftX =
        draft == null ? null : _xForTime(draft.timeMs, plotW);
    if (draft != null && draftX != null && crosshair != null) {
      _dashed(
        canvas,
        Offset(draftX, y(draft.price)),
        crosshair!,
        drawingColor,
      );
    }

    final last = candles.last;
    final lastY = y(last.close);
    if (lastY >= topPad && lastY <= topPad + plotH) {
      final color = last.isUp ? style.bull : style.bear;
      _dashed(
        canvas,
        Offset(0, lastY),
        Offset(plotW, lastY),
        color.withAlpha(150),
      );
      _axisTag(
        canvas,
        size,
        plotW,
        lastY,
        last.close.toStringAsFixed(decimals),
        color,
      );
    }

    for (final time in [entryTime, exitTime]) {
      if (time == null) continue;
      final index = _nearestIndex(time);
      if (index == null) continue;
      final tx = x(index.toDouble());
      if (tx < 0 || tx > plotW) continue;
      _dashed(
        canvas,
        Offset(tx, topPad),
        Offset(tx, topPad + plotH),
        style.axis,
      );
    }

    final levels = <(_Marker, double?, Color, String)>[
      (_Marker.entry, entry, AppColors.primary, 'E'),
      (_Marker.stop, stop, AppColors.danger, 'SL'),
      (_Marker.take, take, AppColors.success, 'TP'),
      (_Marker.exit, exit, AppColors.muted, 'X'),
    ];
    for (final (marker, price, color, label) in levels) {
      if (price == null) continue;
      final ly = y(price);
      if (ly < topPad - 2 || ly > topPad + plotH + 2) continue;
      final active = dragging == marker;
      canvas.drawLine(
        Offset(0, ly),
        Offset(plotW, ly),
        Paint()
          ..color = color.withAlpha(active ? 255 : 220)
          ..strokeWidth = active ? 2 : 1,
      );
      if (active) {
        canvas.drawCircle(
          Offset(plotW - 4, ly),
          4,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
      }
      _chip(
        canvas,
        '$label ${price.toStringAsFixed(decimals)}',
        Offset(4, ly - 7),
        color,
      );
      _axisTag(
        canvas,
        size,
        plotW,
        ly,
        price.toStringAsFixed(decimals),
        color,
      );
    }

    canvas.drawLine(
      Offset(plotW, 0),
      Offset(plotW, size.height),
      Paint()
        ..color = style.axis
        ..strokeWidth = 0.8,
    );

    final pointer = crosshair;
    if (style.showCrosshair &&
        pointer != null &&
        pointer.dx >= 0 &&
        pointer.dx <= plotW &&
        pointer.dy >= topPad &&
        pointer.dy <= topPad + plotH) {
      _dashed(
        canvas,
        Offset(pointer.dx, topPad),
        Offset(pointer.dx, size.height - bottomPad),
        style.crosshair,
      );
      _dashed(
        canvas,
        Offset(0, pointer.dy),
        Offset(plotW, pointer.dy),
        style.crosshair,
      );
      final price = priceForRatio(
        ratio: (pointer.dy - topPad) / plotH,
        min: minPrice,
        max: maxPrice,
        logScale: style.logScale,
      );
      _axisTag(
        canvas,
        size,
        plotW,
        pointer.dy,
        price.toStringAsFixed(decimals),
        style.text,
      );

      final ratio = (pointer.dx / plotW).clamp(0.0, 1.0).toDouble();
      final index =
          (start + ratio * span).floor().clamp(0, candles.length - 1).toInt();
      final time = candles[index].time.toLocal();
      final text = interval.size < const Duration(days: 1)
          ? DateFormat('HH:mm').format(time)
          : DateFormat('d MMM').format(time);
      _bottomTag(canvas, size, pointer.dx, text);
    }

    final picks = <double>[start, start + span / 2, start + span - 1];
    for (final raw in picks) {
      final index = raw.floor().clamp(0, candles.length - 1);
      final time = candles[index].time.toLocal();
      final text = interval.size < const Duration(days: 1)
          ? DateFormat('HH:mm').format(time)
          : DateFormat('d MMM').format(time);
      final painter = _painter(text, color: style.muted, size: 8.5);
      final cx = x(index.toDouble())
          .clamp(0.0, math.max(0.0, plotW - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(cx, size.height - bottomPad + 4));
    }
  }

  void _watermark(Canvas canvas, double plotW, double plotH) {
    final painter = _painter(
      symbol,
      color: style.muted.withAlpha(style.isLight ? 22 : 30),
      size: math.min(72, math.max(28, plotW * 0.2)),
      weight: FontWeight.w800,
    );
    painter.paint(
      canvas,
      Offset(
        plotW / 2 - painter.width / 2,
        topPad + plotH / 2 - painter.height / 2,
      ),
    );
  }

  int? _nearestIndex(DateTime time) {
    final utc = time.toUtc().millisecondsSinceEpoch;
    int? best;
    var bestDelta = double.infinity;
    for (var i = 0; i < candles.length; i++) {
      final delta =
          (candles[i].time.millisecondsSinceEpoch - utc).abs().toDouble();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = i;
      }
    }
    return best;
  }

  void _axisTag(
    Canvas canvas,
    Size size,
    double plotW,
    double cy,
    String text,
    Color color,
  ) {
    final painter = _painter(
      text,
      color: style.background,
      size: 8.5,
      weight: FontWeight.w700,
    );
    final rect = Rect.fromLTWH(plotW + 2, cy - 7, axisWidth - 4, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = color,
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  void _bottomTag(Canvas canvas, Size size, double cx, String text) {
    final painter = _painter(
      text,
      color: style.text,
      size: 8.5,
      weight: FontWeight.w600,
    );
    final width = painter.width + 10;
    final left = (cx - width / 2)
        .clamp(0.0, math.max(0.0, size.width - axisWidth - width))
        .toDouble();
    final rect = Rect.fromLTWH(left, size.height - bottomPad + 3, width, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = style.axis,
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  void _chip(Canvas canvas, String text, Offset offset, Color color) {
    final painter = _painter(
      text,
      color: color,
      size: 8.5,
      weight: FontWeight.w700,
    );
    final rect = Rect.fromLTWH(offset.dx, offset.dy, painter.width + 6, 13);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = style.background.withAlpha(215),
    );
    painter.paint(canvas, Offset(offset.dx + 3, offset.dy + 1.5));
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    if ((from.dx - to.dx).abs() < 0.01) {
      var point = from.dy;
      while (point < to.dy) {
        final end = math.min(point + dash, to.dy);
        canvas.drawLine(Offset(from.dx, point), Offset(from.dx, end), paint);
        point = end + gap;
      }
    } else {
      var point = from.dx;
      while (point < to.dx) {
        final end = math.min(point + dash, to.dx);
        canvas.drawLine(Offset(point, from.dy), Offset(end, from.dy), paint);
        point = end + gap;
      }
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double size,
  }) {
    _painter(text, color: color, size: size).paint(canvas, offset);
  }

  TextPainter _painter(
    String text, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w500,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _TradingChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.start != start ||
        oldDelegate.span != span ||
        oldDelegate.entry != entry ||
        oldDelegate.exit != exit ||
        oldDelegate.stop != stop ||
        oldDelegate.take != take ||
        oldDelegate.entryTime != entryTime ||
        oldDelegate.exitTime != exitTime ||
        oldDelegate.crosshair != crosshair ||
        oldDelegate.dragging != dragging ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.interval != interval ||
        oldDelegate.style != style ||
        oldDelegate.symbol != symbol;
  }
}

/// Preset preview: three mini candles on the preset's own background.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final ChartStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniCandle(style.bear, 16),
                const SizedBox(width: 4),
                _miniCandle(style.bull, 10),
                const SizedBox(width: 4),
                _miniCandle(style.bull, 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              style.name,
              style: TextStyle(
                color: style.text,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniCandle(Color color, double height) {
    return Container(
      width: 6,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// One selectable candle colour.
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.text : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
