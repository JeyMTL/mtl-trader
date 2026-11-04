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
import '../core/chart_sessions.dart';
import '../core/chart_theme.dart';
import '../core/chart_view.dart';
import '../core/indicators.dart';
import '../core/instruments.dart';
import '../services/journal_api.dart';
import '../services/market_data.dart';
import '../ui/chart/chart_marker.dart';
import '../ui/chart/chart_painter.dart';
import '../ui/color_wheel.dart';
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

  Marker _active = Marker.entry;
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
    }
    _load(silent: _candles.isNotEmpty, force: true);
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

  void _setLevel(Marker marker, double price) {
    switch (marker) {
      case Marker.entry:
        _entry = price;
        break;
      case Marker.stop:
        _stop = price;
        break;
      case Marker.take:
        _take = price;
        break;
      case Marker.exit:
        _exit = price;
        break;
    }
  }

  void _pin(Marker marker, double price, DateTime time) {
    setState(() {
      _setLevel(marker, price);
      if (marker == Marker.entry) _entryTime = time;
      if (marker == Marker.exit) _exitTime = time;
      _active = switch (marker) {
        Marker.entry => Marker.stop,
        Marker.stop => Marker.take,
        Marker.take => Marker.exit,
        Marker.exit => Marker.exit,
      };
    });
  }

  /// Applies a drag from the canvas. Entry and exit are points on the chart, so
  /// their time moves with the price; stop and take only carry a price.
  void _levelMoved(Marker marker, double price, DateTime? time) {
    setState(() {
      _setLevel(marker, price);
      if (time == null) return;
      if (marker == Marker.entry) _entryTime = time;
      if (marker == Marker.exit) _exitTime = time;
    });
  }

  void _clear(Marker marker) {
    setState(() {
      switch (marker) {
        case Marker.entry:
          _entry = null;
          _entryTime = null;
          break;
        case Marker.stop:
          _stop = null;
          break;
        case Marker.take:
          _take = null;
          break;
        case Marker.exit:
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
      _active = Marker.entry;
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
          // A break between the tools that change the chart and the one that
          // only changes how it fills the screen. Clearing the levels lives in
          // the Levels card now, where the levels are, instead of sitting
          // next to fullscreen under the same finger.
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: AppColors.border,
          ),
          IconButton(
            tooltip: 'Fullscreen',
            onPressed: _candles.isEmpty ? null : _toggleFullscreen,
            icon: const Icon(Icons.fullscreen, size: 21),
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
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: _style.axis,
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
        height: TradingChartPainter.height,
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
      height: expand ? null : TradingChartPainter.height,
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
      onDrawingSelected: (index) => setState(() => _selectedDrawing = index),
      onDrawingMoved: _moveDrawing,
      onDrawingMoveEnd: _finishDrawingMove,
      onReachStart: _loadingOlder ? null : _loadOlder,
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
      _enterReplayWhenAllowed();
    } else {
      _exitReplay();
    }
  }

  Future<void> _enterReplayWhenAllowed() async {
    if (!await _replayAllowed()) return;
    _enterReplay();
  }

  /// Replay is sold with Pro.
  ///
  /// This check is the upgrade prompt, not the enforcement: candles are served
  /// to every plan, and replay is a way of drawing on them. It lives here
  /// because entering replay is the only moment a trader discovers the feature.
  /// A trial counts as Pro, and a stale `pro` label cannot outlive its period.
  Future<bool> _replayAllowed() async {
    try {
      final profile = await JournalApi().profile();
      final status =
          (profile['subscription_status'] as String? ?? '').toLowerCase();
      final tier =
          (profile['subscription_tier'] as String? ?? '').toLowerCase();
      final now = DateTime.now();
      final trialEnd =
          DateTime.tryParse(profile['trial_ends_at'] as String? ?? '');
      final periodEnd =
          DateTime.tryParse(profile['current_period_end'] as String? ?? '');

      final trialing =
          status == 'trial' && trialEnd != null && trialEnd.isAfter(now);
      final subscribed = status == 'active' &&
          periodEnd != null &&
          periodEnd.isAfter(now) &&
          tier == 'pro';
      if (trialing || subscribed) return true;
    } catch (_) {
      // Offline, or a schema still missing the billing columns: fall through to
      // the prompt rather than pretending the feature is paid for.
    }

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Market replay is a Pro feature. Upgrade to Pro to use it.'),
      ),
    );
    return false;
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
        _drawingTool = action == 'trend' ? DrawingTool.trend : DrawingTool.ray;
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
            return _styleSheet(
              _style,
              (next) {
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
              },
              onClose: () => Navigator.of(context).pop(),
            );
          },
        );
      },
    );
  }

  /// The chart style sheet.
  ///
  /// Settings are grouped into cards — theme, chart type, indicators, colours,
  /// sessions, display — because the previous flat column was one long list of
  /// switches with section labels lost between them. Within a card the rows
  /// share one rhythm and hairline dividers, and a control that only belongs to
  /// the switch above it (a study's period, an indicator's lengths) tucks under
  /// that row instead of sitting loose in the list.
  Widget _styleSheet(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged, {
    required VoidCallback onClose,
  }) {
    final studies = style.studies;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chart style',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.instrument.symbol} · remembered for this market',
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => onChanged(ChartStyle.ink),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSection(
                    title: 'Theme',
                    trailing: style.name,
                    children: [
                      Row(
                        children: [
                          for (var i = 0;
                              i < ChartStyle.presets.length;
                              i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _ThemeSwatch(
                                style: ChartStyle.presets[i],
                                selected: ChartStyle.presets[i].id ==
                                        style.id &&
                                    ChartStyle.presets[i].bull == style.bull &&
                                    ChartStyle.presets[i].bear == style.bear,
                                onTap: () => onChanged(ChartStyle.presets[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Chart type',
                    children: [
                      _segmented(
                        selected: style.chartType,
                        options: [
                          for (final type in ChartType.values)
                            (value: type, label: type.label),
                        ],
                        onSelect: (type) =>
                            onChanged(style.copyWith(chartType: type)),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Indicators',
                    trailing: studies.isEmpty ? 'none' : '${studies.length} on',
                    children: [
                      for (final study in OverlayStudy.values) ...[
                        _switchRow(
                          studyLabel(
                            study,
                            period: style.periodFor(study),
                          ),
                          studies.contains(study),
                          (value) => onChanged(
                            style.copyWith(
                              studies: value
                                  ? {...studies, study}
                                  : ({...studies}..remove(study)),
                            ),
                          ),
                        ),
                        if (studies.contains(study))
                          _tucked(
                            _labelledControl(
                              'Period',
                              _stepper(
                                value: style.periodFor(study),
                                min: 2,
                                max: 400,
                                onChanged: (value) => onChanged(
                                  style.copyWith(
                                    studyPeriods: {
                                      ...style.studyPeriods,
                                      study.name: value,
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                      _switchRow(
                        'Volume',
                        style.showVolume,
                        (value) => onChanged(style.copyWith(showVolume: value)),
                      ),
                      const SizedBox(height: 6),
                      _subLabel('Lower pane'),
                      const SizedBox(height: 6),
                      _segmented(
                        selected: style.oscillator,
                        options: [
                          for (final oscillator in Oscillator.values)
                            (value: oscillator, label: oscillator.label),
                        ],
                        onSelect: (oscillator) => onChanged(
                          style.copyWith(oscillator: oscillator),
                        ),
                      ),
                      if (style.oscillator == Oscillator.rsi)
                        _tucked(
                          _labelledControl(
                            'RSI period',
                            _stepper(
                              value: style.rsiPeriod,
                              min: 2,
                              max: 100,
                              onChanged: (value) => onChanged(
                                style.copyWith(rsiPeriod: value),
                              ),
                            ),
                          ),
                        ),
                      if (style.oscillator == Oscillator.macd) ...[
                        _tucked(
                          _labelledControl(
                            'Fast',
                            _stepper(
                              value: style.macdFast,
                              min: 2,
                              max: 60,
                              onChanged: (value) => onChanged(
                                style.copyWith(macdFast: value),
                              ),
                            ),
                          ),
                        ),
                        _tucked(
                          _labelledControl(
                            'Slow',
                            _stepper(
                              value: style.macdSlow,
                              min: 3,
                              max: 120,
                              onChanged: (value) => onChanged(
                                style.copyWith(macdSlow: value),
                              ),
                            ),
                          ),
                        ),
                        _tucked(
                          _labelledControl(
                            'Signal',
                            _stepper(
                              value: style.macdSignal,
                              min: 2,
                              max: 60,
                              onChanged: (value) => onChanged(
                                style.copyWith(macdSignal: value),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SettingsSection(
                    title: 'Candle colours',
                    children: [
                      _colorRow('Up', style.bull, (color) {
                        onChanged(style.copyWith(bull: color));
                      }),
                      _colorRow('Down', style.bear, (color) {
                        onChanged(style.copyWith(bear: color));
                      }),
                    ],
                  ),
                  SettingsSection(
                    title: 'Sessions',
                    children: [
                      _switchRow(
                        'Session shading',
                        style.showSessions,
                        (value) =>
                            onChanged(style.copyWith(showSessions: value)),
                      ),
                      if (style.showSessions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final session in TradingSession.values)
                                _StylePill(
                                  label: session.label,
                                  selected: style.sessions.contains(session),
                                  accent: session.tint,
                                  onTap: () {
                                    final next = <TradingSession>{
                                      ...style.sessions,
                                    };
                                    if (next.contains(session)) {
                                      next.remove(session);
                                    } else {
                                      next.add(session);
                                    }
                                    onChanged(style.copyWith(sessions: next));
                                  },
                                ),
                            ],
                          ),
                        ),
                      _hairline(),
                      _switchRow(
                        'Session break lines',
                        style.showSessionBreaks,
                        (value) => onChanged(
                          style.copyWith(showSessionBreaks: value),
                        ),
                      ),
                      _hairline(),
                      _switchRow(
                        'Period separators',
                        style.showSeparators,
                        (value) =>
                            onChanged(style.copyWith(showSeparators: value)),
                      ),
                      if (style.showSeparators)
                        _tucked(
                          _segmented(
                            selected: style.separatorGrain,
                            options: [
                              for (final grain in SeparatorGrain.values)
                                (value: grain, label: grain.label),
                            ],
                            onSelect: (grain) => onChanged(
                              style.copyWith(separatorGrain: grain),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Display',
                    children: [
                      _switchRow(
                        'Grid lines',
                        style.showGrid,
                        (value) => onChanged(style.copyWith(showGrid: value)),
                      ),
                      _hairline(),
                      _switchRow(
                        'Crosshair',
                        style.showCrosshair,
                        (value) =>
                            onChanged(style.copyWith(showCrosshair: value)),
                      ),
                      _hairline(),
                      _switchRow(
                        'Watermark',
                        style.showWatermark,
                        (value) =>
                            onChanged(style.copyWith(showWatermark: value)),
                      ),
                      _hairline(),
                      _switchRow(
                        'Logarithmic price axis',
                        style.logScale,
                        (value) => onChanged(style.copyWith(logScale: value)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: ElevatedButton(
              onPressed: onClose,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hairline() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 1),
        color: AppColors.border.withAlpha(130),
      );

  Widget _subLabel(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );

  /// A control that only exists because of the row above it, indented under a
  /// rule so it reads as that row's detail rather than a new setting.
  Widget _tucked(Widget child) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.border, width: 2),
        ),
      ),
      child: child,
    );
  }

  Widget _labelledControl(String label, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: _subLabel(label)),
          const SizedBox(width: 8),
          control,
        ],
      ),
    );
  }

  Widget _stepper({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return _Stepper(
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }

  Widget _segmented<T>({
    required T selected,
    required List<({T value, String label})> options,
    required ValueChanged<T> onSelect,
  }) {
    return _Segmented(
      items: [
        for (final option in options)
          _SegmentedOption(
            label: option.label,
            selected: option.value == selected,
            onTap: () => onSelect(option.value),
          ),
      ],
    );
  }

  Widget _colorRow(String title, Color current, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
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
                // Any colour, not just the ten on somebody else's shortlist.
                // The wheel opens on the current colour, so nudging a shade
                // stays a nudge instead of starting from scratch.
                _WheelDot(
                  current: current,
                  known: ChartStyle.candlePalette.contains(current),
                  onTap: () => _pickCustomColor(title, current, onPick),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomColor(
    String title,
    Color current,
    ValueChanged<Color> onPick,
  ) async {
    final picked = await showColorWheelPicker(
      context,
      initial: current,
      title: '$title colour',
      quickPicks: ChartStyle.candlePalette,
    );
    if (picked != null) onPick(picked);
  }

  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
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
    return SizedBox(height: TradingChartPainter.height, child: content);
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
              const SizedBox(width: 8),
              // Expanded instead of Spacer: the timestamp is the part that has
              // to give way when the pills and a doubled text size leave no
              // room, and a Spacer only reports the overflow.
              Expanded(
                child: _updated == null
                    ? const SizedBox.shrink()
                    : Text(
                        'Updated ${DateFormat('HH:mm:ss').format(_updated!)}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tabular.copyWith(
                          color: AppColors.faint,
                          fontSize: 9.5,
                        ),
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
            Expanded(
              child: Text(
                'TIME FRAME',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: idleInk,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
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

  String _labelFor(Marker marker) {
    switch (marker) {
      case Marker.entry:
        return 'entry';
      case Marker.stop:
        return 'stop';
      case Marker.take:
        return 'target';
      case Marker.exit:
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
          SectionTitle(
            title: 'Levels',
            subtitle:
                'Tap a row, then tap the chart where that level sat. Hold a line to move it — for entry and exit the time moves too. Nothing reaches the form until you confirm.',
            trailing: _entry == null &&
                    _stop == null &&
                    _take == null &&
                    _exit == null
                ? null
                : TextButton(
                    onPressed: _reset,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear all'),
                  ),
          ),
          const SizedBox(height: 8),
          _LevelRow(
            label: 'Entry',
            price: _entry,
            time: _entryTime,
            instrument: instrument,
            color: AppColors.primary,
            active: _active == Marker.entry,
            onSelect: () => setState(() => _active = Marker.entry),
            onClear: _entry == null ? null : () => _clear(Marker.entry),
          ),
          const SizedBox(height: 6),
          _LevelRow(
            label: 'Stop loss',
            price: _stop,
            instrument: instrument,
            color: AppColors.danger,
            active: _active == Marker.stop,
            onSelect: () => setState(() => _active = Marker.stop),
            onClear: _stop == null ? null : () => _clear(Marker.stop),
          ),
          const SizedBox(height: 6),
          _LevelRow(
            label: 'Take profit',
            price: _take,
            instrument: instrument,
            color: AppColors.success,
            active: _active == Marker.take,
            onSelect: () => setState(() => _active = Marker.take),
            onClear: _take == null ? null : () => _clear(Marker.take),
          ),
          const SizedBox(height: 6),
          _LevelRow(
            label: 'Exit',
            price: _exit,
            time: _exitTime,
            instrument: instrument,
            color: AppColors.muted,
            active: _active == Marker.exit,
            onSelect: () => setState(() => _active = Marker.exit),
            onClear: _exit == null ? null : () => _clear(Marker.exit),
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
    this.onReachStart,
  });

  final List<Candle> candles;
  final ChartInterval interval;
  final int decimals;
  final String symbol;
  final ChartStyle style;

  /// Fixed canvas height, or null to fill the space the parent offers (the
  /// fullscreen layout).
  final double? height;

  /// Fired when a pan reaches the oldest loaded bar, so the screen can fetch an
  /// earlier window instead of the chart dead-ending at the left edge.
  final VoidCallback? onReachStart;
  final Marker active;
  final double? entry;
  final double? stop;
  final double? take;
  final double? exit;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final ValueChanged<Marker> onSelect;
  final void Function(Marker marker, double price, DateTime time) onPin;
  final void Function(Marker marker, double price, DateTime? time) onLevelMoved;
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

class _ChartCanvasState extends State<_ChartCanvas>
    with SingleTickerProviderStateMixin {
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
  Marker? _dragging;
  int? _drawingIndex;
  ChartDrawing? _drawingOriginal;
  Offset _dragOrigin = Offset.zero;
  double _baseSpan = 0;
  double _baseStart = 0;

  /// Manual vertical offset of the price window, as a share of the visible
  /// range. Zero is auto-fit, which is what the chart does by default; dragging
  /// up or down moves the price axis without touching the time axis, the way a
  /// desktop terminal does.
  double _pricePan = 0;

  /// Drives the coast after a fling and the short spring onto a whole bar.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )
    ..addListener(_onSettleTick)
    ..addStatusListener(_onSettleStatus);
  double _settleFrom = 0;
  double _settleTo = 0;
  bool _thenSnap = false;

  @override
  void initState() {
    super.initState();
    _syncLevels();
    _view.fit(widget.candles.length);
    _rebuildStudies();
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles) ||
        oldWidget.interval != widget.interval) {
      final oldLength = oldWidget.candles.length;
      if (oldLength == 0 || oldWidget.interval != widget.interval) {
        // First data, or a different candle size: show the newest bars, and drop
        // any manual price offset since the range has changed underneath it.
        _pricePan = 0;
        _view.fit(widget.candles.length);
      } else if (_view.isAtEdge(oldLength)) {
        // Watching the live edge, so keep following it as bars arrive.
        _view.pinToEdge(widget.candles.length);
      } else {
        // The trader panned back. Hold the bar that was under the left edge,
        // because the window slid underneath the viewport and keeping the same
        // index would creep towards the newest candle on every refresh.
        final left = _view.start.floor().clamp(0, oldLength - 1);
        final fraction = _view.start - left;
        final anchor = oldWidget.candles[left].time;
        final next = widget.candles
            .indexWhere((candle) => !candle.time.isBefore(anchor));
        _view.anchorLeftEdge(
          next < 0 ? 0 : next + fraction,
          widget.candles.length,
        );
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
    var low = min - pad;
    var high = max + pad;

    // A manual vertical drag shifts the window by a share of its own range, so
    // the zoom is untouched and the axis labels travel with the candles.
    if (_pricePan != 0) {
      final shift = (high - low) * _pricePan;
      low += shift;
      high += shift;
    }
    return (min: low, max: high);
  }

  double _priceFor(Offset local) {
    final bounds = _bounds();
    final panes = TradingChartPainter.paneLayout(_size.height, widget.style);
    if (panes.priceH <= 0) return bounds.max;
    final ratio =
        ((local.dy - panes.priceTop) / panes.priceH).clamp(0.0, 1.0).toDouble();
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
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (plotW <= 0) return null;
    final ratio = (local.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, widget.candles.length);
    return widget.candles[index].time.toLocal();
  }

  double _yFor(double price) {
    final bounds = _bounds();
    final panes = TradingChartPainter.paneLayout(_size.height, widget.style);
    return panes.priceTop +
        ratioForPrice(
              price: price,
              min: bounds.min,
              max: bounds.max,
              logScale: widget.style.logScale,
            ) *
            panes.priceH;
  }

  void _setDraft(Marker marker, double price) {
    switch (marker) {
      case Marker.entry:
        _entry = price;
        break;
      case Marker.stop:
        _stop = price;
        break;
      case Marker.take:
        _take = price;
        break;
      case Marker.exit:
        _exit = price;
        break;
    }
  }

  void _tap(Offset local) {
    if (widget.candles.isEmpty) return;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (plotW <= 0 || local.dx > plotW) return;
    if (widget.drawTool == DrawingTool.none && widget.selectedDrawing != null) {
      widget.onDrawingSelected(null);
    }
    if (widget.drawTool != DrawingTool.none) {
      final panes = TradingChartPainter.paneLayout(_size.height, widget.style);
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
      if (widget.active == Marker.entry) _entryTime = time;
      if (widget.active == Marker.exit) _exitTime = time;
    });
    widget.onPin(widget.active, price, time);
  }

  void _onScaleStart(ScaleStartDetails details) {
    // A new touch owns the chart: stop the coast where it is.
    _settle.stop();
    _baseSpan = _view.span;
    _baseStart = _view.start;
  }

  void _onSettleTick() {
    if (widget.candles.isEmpty) return;
    if (_dragging != null || _drawingIndex != null) {
      _settle.stop();
      return;
    }
    final t = Curves.easeOutCubic.transform(_settle.value);
    setState(() => _view.start = _settleFrom + (_settleTo - _settleFrom) * t);
    _view.clampTo(widget.candles.length);
    // Coasting into the oldest bar keeps pulling history in, so a long fling
    // does not stop at the edge of the loaded window.
    if (_view.isAtStart) widget.onReachStart?.call();
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_thenSnap) {
      _thenSnap = false;
      final target = _view.start.roundToDouble();
      if ((target - _view.start).abs() > 0.001) {
        _animateStartTo(target, 130);
        return;
      }
    }
    setState(() => _view.snap(widget.candles.length));
  }

  void _animateStartTo(double target, int millis, {bool thenSnap = false}) {
    _settleFrom = _view.start;
    _settleTo = target;
    _thenSnap = thenSnap;
    _settle
      ..duration = Duration(milliseconds: millis)
      ..forward(from: 0);
  }

  /// Lift-off: the finger's speed becomes candle travel with friction, then the
  /// window settles onto a whole bar instead of resting between two.
  void _onScaleEnd(ScaleEndDetails details) {
    setState(() => _crosshair = null);
    final count = widget.candles.length;
    if (count < 2 || _dragging != null || _drawingIndex != null) return;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (plotW <= 0) return;

    // Finger moving right moves the chart right, which walks the window back.
    final perSecond = -details.velocity.pixelsPerSecond.dx / plotW * _view.span;
    if (perSecond.abs() < 4) {
      // Too slow to be a throw: just sit on the nearest bar.
      _animateStartTo(_view.start.roundToDouble(), 120);
      return;
    }
    _animateStartTo(_view.flingRest(perSecond, count), 420, thenSnap: true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.candles.length < 2) return;
    final plotW = _size.width - TradingChartPainter.axisWidth;
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
        // Dragged onto the oldest loaded bar: ask for an earlier window, so the
        // chart keeps moving instead of stopping at the edge of the fetch.
        if (_view.isAtStart) widget.onReachStart?.call();

        // The vertical component moves the price axis. Without this the only
        // way to see a wick off the top of the pane is to pinch and lose the
        // time span you were reading.
        final panes = TradingChartPainter.paneLayout(
          _size.height,
          widget.style,
        );
        if (panes.priceH > 0) {
          _pricePan = (_pricePan + details.focalPointDelta.dy / panes.priceH)
              .clamp(-1.5, 1.5)
              .toDouble();
        }
      }
      _crosshair = details.localFocalPoint;
    });
  }

  Marker? _nearestLevel(Offset local) {
    double? bestDistance;
    Marker? best;
    void check(Marker marker, double? price) {
      if (price == null) return;
      final dy = (_yFor(price) - local.dy).abs();
      if (dy <= 22 && (bestDistance == null || dy < bestDistance!)) {
        bestDistance = dy;
        best = marker;
      }
    }

    check(Marker.entry, _entry);
    check(Marker.stop, _stop);
    check(Marker.take, _take);
    check(Marker.exit, _exit);
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
    final t =
        (((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / lengthSquared)
            .clamp(0.0, 1.0);
    return (point - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
  }

  int? _nearestDrawing(Offset local) {
    final plotW = _size.width - TradingChartPainter.axisWidth;
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
    final plotW = _size.width - TradingChartPainter.axisWidth;
    final shift =
        plotW <= 0 ? 0.0 : (local.dx - _dragOrigin.dx) / plotW * _view.span;
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
        if (marker == Marker.entry) _entryTime = time;
        if (marker == Marker.exit) _exitTime = time;
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
      Marker.entry => _entry,
      Marker.stop => _stop,
      Marker.take => _take,
      Marker.exit => _exit,
    };
    if (price == null) return;
    // Only the point markers carry a time; the parent ignores it for stop/take.
    final time = switch (marker) {
      Marker.entry => _entryTime,
      Marker.exit => _exitTime,
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
      return const SizedBox(height: TradingChartPainter.height);
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
            onScaleEnd: _onScaleEnd,
            onLongPressStart: (details) => _startDrag(details.localPosition),
            onLongPressMoveUpdate: (details) =>
                _updateDrag(details.localPosition),
            onLongPressEnd: (details) => _endDrag(details.localPosition),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: TradingChartPainter(
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
                  right: TradingChartPainter.axisWidth + 6,
                  child: IgnorePointer(child: _readout()),
                ),
                // A shifted price axis: the same affordance as LIVE, so the
                // trader is never stuck with a scale they cannot undo.
                if (_pricePan != 0)
                  Positioned(
                    right: TradingChartPainter.axisWidth + 6,
                    bottom: 34,
                    child: Semantics(
                      button: true,
                      label: 'Fit the price scale',
                      child: GestureDetector(
                        onTap: () => setState(() => _pricePan = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.style.background.withAlpha(225),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: widget.style.axis),
                          ),
                          child: Text(
                            'AUTO ↺',
                            style: TextStyle(
                              color: widget.style.text,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Panned back into history: one tap returns to the newest bars,
                // which is otherwise a long drag the trader has to guess at.
                if (!_view.isAtEdge(widget.candles.length))
                  Positioned(
                    right: TradingChartPainter.axisWidth + 6,
                    bottom: 6,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _view.pinToEdge(widget.candles.length);
                        _crosshair = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.style.background.withAlpha(225),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: widget.style.axis),
                        ),
                        child: Text(
                          'LIVE →',
                          style: TextStyle(
                            color: widget.style.text,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _readout() {
    final plotW = _size.width - TradingChartPainter.axisWidth;
    final ratio = _crosshair == null || plotW <= 0
        ? 1.0
        : (_crosshair!.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, widget.candles.length);
    final candle = widget.candles[index];
    final color = candle.isUp ? widget.style.bull : widget.style.bear;

    // Session the crosshair is sitting in, and how far the session has moved
    // since its first candle. The journal owns trade P&L; the chart's job is to
    // say which market this bar belongs to and what that market has done.
    String? sessionLabel;
    Color? sessionColor;
    if (widget.style.showSessions) {
      final hit = sessionHitOf(
        index: index,
        length: widget.candles.length,
        timeAt: (i) => widget.candles[i].time,
      );
      if (hit != null) {
        final open = widget.candles[hit.firstIndex].open;
        final move = open == 0 ? 0.0 : (candle.close - open) / open * 100;
        sessionLabel =
            '${hit.session.label} ${move >= 0 ? '+' : ''}${move.toStringAsFixed(2)}%';
        sessionColor = hit.session.tint;
      }
    }

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
            if (sessionLabel != null && sessionColor != null)
              TextSpan(
                text: '   · $sessionLabel',
                style: TextStyle(
                  color: sessionColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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

/// A small switch-style pill, used where an option can be toggled on its own
/// (the sessions) rather than picked from a list of one.
class _StylePill extends StatelessWidget {
  const _StylePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The pill's own colour when selected. Sessions keep their chart tint here,
  /// so the shading on the canvas and the chip that switches it on match.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? tone.withAlpha(26) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? tone.withAlpha(180) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? (accent == null ? AppColors.primaryLight : tone)
                : AppColors.muted,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One choice inside a [_Segmented] control.
class _SegmentedOption {
  const _SegmentedOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// An exclusive choice laid out as one track, so "which one is on" is read from
/// a single moving block instead of from two separate outlined chips.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.items});

  final List<_SegmentedOption> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: item.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: item.selected
                        ? AppColors.primary.withAlpha(28)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.field - 3),
                    border: Border.all(
                      color: item.selected
                          ? AppColors.primary.withAlpha(150)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: item.selected
                          ? AppColors.primaryLight
                          : AppColors.muted,
                      fontSize: 11.5,
                      fontWeight:
                          item.selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact −/value/+ control for periods and indicator lengths.
///
/// It is one pill rather than two loose icon buttons, so a row of them lines up
/// with the switches above and below instead of breaking the column's rhythm.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            Icons.remove,
            'Decrease',
            value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: tabular.copyWith(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _button(
            Icons.add,
            'Increase',
            value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback? onTap) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 30,
          child: Icon(
            icon,
            size: 15,
            color:
                onTap == null ? AppColors.faint.withAlpha(90) : AppColors.muted,
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

/// Test-only handle on the canvas painter.
///
/// The painter is private because nothing outside this file should build one,
/// but a benchmark that copies its loops measures the copy. This lets
/// `test/perf/chart_paint_benchmark.dart` time the real paint path — candles,
/// studies, bands, axes and labels — through a `PictureRecorder`.
@visibleForTesting
CustomPainter debugChartPainter({
  required List<Candle> candles,
  required double start,
  required double span,
  required double minPrice,
  required double maxPrice,
  required int decimals,
  required ChartInterval interval,
  required ChartStyle style,
  String symbol = 'EURUSD',
}) {
  return TradingChartPainter(
    candles: candles,
    start: start,
    span: span,
    minPrice: minPrice,
    maxPrice: maxPrice,
    entry: null,
    exit: null,
    stop: null,
    take: null,
    entryTime: null,
    exitTime: null,
    crosshair: null,
    dragging: null,
    decimals: decimals,
    interval: interval,
    chartType: style.chartType,
    studies: const {},
    drawings: const [],
    draftStart: null,
    style: style,
    symbol: symbol,
    selectedDrawing: null,
  );
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
/// The way into the colour wheel from a swatch row.
///
/// It doubles as the "custom colour" indicator: when the current colour is not
/// one of the palette dots, this one wears it, so a colour chosen from the wheel
/// shows up as the selection instead of nothing being selected at all.
class _WheelDot extends StatelessWidget {
  const _WheelDot({
    required this.current,
    required this.known,
    required this.onTap,
  });

  final Color current;
  final bool known;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = current.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: known ? AppColors.surfaceAlt : current,
          shape: BoxShape.circle,
          border: Border.all(
            color: known ? AppColors.border : ink,
            width: known ? 1 : 2,
          ),
        ),
        child: Icon(
          Icons.colorize,
          size: 14,
          color: known ? AppColors.muted : ink,
        ),
      ),
    );
  }
}

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
