import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/chart_replay.dart';
import '../core/chart_theme.dart';
import '../core/chart_view.dart';
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

  ChartRange _range = ChartRange.oneDay;
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

  /// How much history one range-sized request covers, and therefore how far a
  /// jump or a page-back reaches.
  Duration get _rangeSpan {
    switch (_range) {
      case ChartRange.oneDay:
        return const Duration(days: 1);
      case ChartRange.fiveDays:
        return const Duration(days: 5);
      case ChartRange.oneMonth:
        return const Duration(days: 30);
    }
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
    final cached = _market.cached(widget.instrument, _range);
    if (cached != null && cached.isNotEmpty) {
      _candles = cached;
      _loading = false;
    }
    _load(silent: _candles.isNotEmpty, force: true);

    if (widget.instrument.isLive) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _load(silent: true),
      );
    }
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

  Future<void> _load({bool silent = false, bool force = false}) async {
    try {
      final candles = await _market.candles(
        widget.instrument,
        _range,
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

  void _pickRange(ChartRange range) {
    if (range == _range) return;
    // Replay belongs to the candles it started on; a new range starts clean.
    _stopPlay();
    final cached = _market.cached(widget.instrument, range);
    setState(() {
      _range = range;
      _replay = null;
      _error = null;
      _candles = cached ?? const [];
      _loading = cached == null || cached.isEmpty;
    });
    _load(silent: cached != null && cached.isNotEmpty);
  }

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
                _ranges(),
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
                _disclaimer(instrument),
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
                      ? '${instrument.name} · ${_range.interval}'
                      : '${parts.join('  ')}  · ${_range.interval}',
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
          _ranges(overlay: true),
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
      range: _range,
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
    if (!loaded) {
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

  /// Replaces the series with one range-sized window. False means the range has
  /// no candles there (a weekend, a holiday, before the instrument existed).
  Future<bool> _loadWindow({
    required DateTime start,
    required DateTime end,
  }) async {
    setState(() => _loading = true);
    try {
      final candles = await _market.candles(
        widget.instrument,
        _range,
        from: start,
        to: end,
        force: true,
      );
      if (!mounted) return false;
      setState(() {
        _candles = candles;
        _loading = false;
        _error = null;
      });
      return candles.isNotEmpty;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return false;
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
        _range,
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
    if (widget.instrument.isLive && _refreshTimer == null) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _load(silent: true),
      );
    }
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
              // Persist in the background; the sheet repaints immediately.
              unawaited(ChartStyle.save());
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
          ],
        ),
      ),
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
                text: instrument.isLive ? 'LIVE' : 'DELAYED',
                tone: instrument.isLive ? Tone.positive : Tone.muted,
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

  Widget _ranges({bool overlay = false}) {
    // On the fullscreen canvas the chips sit on the chart itself, so they take
    // the chart's palette instead of the app's surface colour.
    final chipBackground = overlay ? _style.background : AppColors.surface;
    final chipBorder = overlay ? _style.axis : AppColors.border;
    final activeFill =
        overlay ? _style.text.withAlpha(26) : AppColors.primary.withAlpha(30);
    final activeInk = overlay ? _style.text : AppColors.primaryLight;
    final idleInk = overlay ? _style.muted : AppColors.muted;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: chipBorder),
      ),
      child: Row(
        children: [
          for (final range in ChartRange.values)
            Expanded(
              child: InkWell(
                onTap: () => _pickRange(range),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: range == _range ? activeFill : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    range.label,
                    style: TextStyle(
                      color: range == _range ? activeInk : idleInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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

  Widget _disclaimer(Instrument instrument) {
    final strong = instrument.isIndex;
    final live = instrument.isLive;
    final accent = live
        ? AppColors.success
        : strong
            ? AppColors.primary
            : AppColors.faint;
    return FlatCard(
      padding: const EdgeInsets.all(12),
      borderColor: accent.withAlpha(live || strong ? 70 : 34),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              live
                  ? 'Free live feed for spot forex and crypto, refreshed every minute. The broker price still decides the fill — confirm it before you act.'
                  : strong
                      ? 'Index charts are delayed. They are here so you can pin your levels quickly — not to time an entry or judge live price.'
                      : 'This instrument is exchange-traded, so its free chart is delayed. Use it to pin levels, not to read live price.',
              style: TextStyle(
                color: live || strong ? AppColors.muted : AppColors.faint,
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
    required this.range,
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
    this.height,
  });

  final List<Candle> candles;
  final ChartRange range;
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
  _Marker? _dragging;
  double _baseSpan = 0;
  double _baseStart = 0;

  @override
  void initState() {
    super.initState();
    _syncLevels();
    _view.fit(widget.candles.length);
  }

  @override
  void didUpdateWidget(covariant _ChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles) ||
        oldWidget.range != widget.range) {
      if (oldWidget.candles.isEmpty || oldWidget.range != widget.range) {
        _view.fit(widget.candles.length);
      } else {
        _view.clampTo(widget.candles.length);
      }
    }
    if (_dragging == null) _syncLevels();
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
    final plotH = _size.height -
        _TradingChartPainter.topPad -
        _TradingChartPainter.bottomPad;
    if (plotH <= 0) return bounds.max;
    final ratio = ((local.dy - _TradingChartPainter.topPad) / plotH)
        .clamp(0.0, 1.0)
        .toDouble();
    return bounds.max - ratio * (bounds.max - bounds.min);
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
    final plotH = _size.height -
        _TradingChartPainter.topPad -
        _TradingChartPainter.bottomPad;
    final spread = math.max(1e-9, bounds.max - bounds.min);
    return _TradingChartPainter.topPad + (bounds.max - price) / spread * plotH;
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

  void _startDrag(Offset local) {
    final marker = _nearestLevel(local);
    setState(() {
      _crosshair = local;
      if (marker != null) {
        _dragging = marker;
      }
    });
    if (marker != null) widget.onSelect(marker);
  }

  void _updateDrag(Offset local) {
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
                      range: widget.range,
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
              text: '· ${widget.range.interval}  ',
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
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
    required this.range,
    required this.style,
    required this.symbol,
  });

  static const double height = 380;
  static const double axisWidth = 58;
  static const double topPad = 10;
  static const double bottomPad = 20;

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
  final ChartRange range;
  final ChartStyle style;
  final String symbol;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.background);
    final plotW = size.width - axisWidth;
    final plotH = size.height - topPad - bottomPad;
    if (candles.isEmpty || plotW <= 0 || plotH <= 0) return;

    if (style.showWatermark) _watermark(canvas, plotW, plotH);

    final spread =
        (maxPrice - minPrice).abs() < 1e-9 ? 1.0 : maxPrice - minPrice;
    double y(double price) => topPad + (maxPrice - price) / spread * plotH;
    double x(double index) => ((index + 0.5 - start) / span) * plotW;

    final grid = Paint()
      ..color = style.grid
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final gy = topPad + plotH * i / 4;
      if (style.showGrid) {
        canvas.drawLine(Offset(0, gy), Offset(plotW, gy), grid);
      }
      final price = maxPrice - spread * i / 4;
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
        Offset(pointer.dx, topPad + plotH),
        style.crosshair,
      );
      _dashed(
        canvas,
        Offset(0, pointer.dy),
        Offset(plotW, pointer.dy),
        style.crosshair,
      );
      final price = maxPrice - (pointer.dy - topPad) / plotH * spread;
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
      final text = range == ChartRange.oneDay
          ? DateFormat('HH:mm').format(time)
          : DateFormat('d MMM HH:mm').format(time);
      _bottomTag(canvas, size, pointer.dx, text);
    }

    final picks = <double>[start, start + span / 2, start + span - 1];
    for (final raw in picks) {
      final index = raw.floor().clamp(0, candles.length - 1);
      final time = candles[index].time.toLocal();
      final text = range == ChartRange.oneDay
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
        oldDelegate.range != range ||
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
