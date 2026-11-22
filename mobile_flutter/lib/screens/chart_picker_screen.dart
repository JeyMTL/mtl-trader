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
import '../core/chart_zone.dart';
import '../core/indicators.dart';
import '../core/level_touch.dart';
import '../core/trade_exit.dart' show ResolvedExit;
import '../core/instruments.dart';
import '../services/journal_api.dart';
import '../services/alerts.dart';
import '../services/chart_drawings_sync.dart';
import '../services/market_data.dart';
import '../ui/chart/chart_marker.dart';
import '../ui/chart/chart_painter.dart';
import '../ui/chart/drawings_sheet.dart';
import '../ui/chart/sync_badge.dart';
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
    this.direction,
  });

  final double? entry;
  final double? exit;
  final double? stop;
  final double? take;
  final DateTime? entryTime;
  final DateTime? exitTime;

  /// `BUY` or `SELL` when the levels came from a long/short position tool, so
  /// the form follows the side of the box rather than the side it opened with.
  final String? direction;

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
    this.debugSyncState,
  });

  final Instrument instrument;
  final String direction;
  final double? entry;
  final double? exit;
  final double? stop;
  final double? take;

  /// Pins the sync badge to one state for a widget test.
  ///
  /// Null in production, where the badge follows the real reconciliation. A test
  /// cannot reach the other states on its own: `saved` needs a successful sync
  /// and `syncing` a read in flight, and neither exists without a network and a
  /// session.
  @visibleForTesting
  final ChartSyncState? debugSyncState;

  @override
  State<ChartPickerScreen> createState() => _ChartPickerScreenState();
}

class _ChartPickerScreenState extends State<ChartPickerScreen> {
  final _market = MarketDataService();

  ChartInterval _interval = ChartInterval.fiveMinutes;

  /// Lines and boxes the trader has drawn on this instrument.
  List<ChartDrawing> _drawings = const [];

  /// Keeps this chart's objects in step with the account copy the web desk
  /// writes. Debounced, and never allowed to fail loudly.
  final ChartDrawingsSync _cloudDrawings = ChartDrawingsSync();
  Timer? _cloudSyncTimer;
  bool _cloudSyncRunning = false;
  bool _cloudSyncAgain = false;

  /// Signature of each object as last written, keyed by row id (or its content
  /// for one that has not been shared yet). Drives the edit timestamps.
  final Map<String, String> _drawingVersions = {};
  Timer? _syncHideTimer;

  /// What the account copy is doing, shown as one small badge in the app bar
  /// and again over the fullscreen chart.
  ChartSyncState _syncState = ChartSyncState.idle;
  String? _syncMessage;

  /// Drawing under the trader's finger, selected for drag, edit or delete.
  int? _selectedDrawing;

  /// One step of undo is one whole list, because a drag commits on every frame
  /// and a trader thinks in edits, not frames. Redo is cleared by the next edit,
  /// exactly as it is everywhere else.
  final List<List<ChartDrawing>> _redo = [];

  /// Snap to a wick while dragging. On by default, as on a desk, but a trader
  /// marking a fill that printed between two ticks needs it off.
  bool _magnet = true;

  /// Candle under the crosshair, so the header can show its O H L C the way a
  /// desktop chart does while the pointer travels.
  Candle? _hover;

  /// When the candles on screen are the device's last copy rather than a live
  /// read, this is the moment they were fetched. Null means what is painted is
  /// the market as the feed just served it.
  DateTime? _staleAt;

  /// Whether the finger has put down the first point of the object being
  /// placed. Only the banner needs it, and only to count.
  bool _placing = false;

  /// Tool picked from the sheet, waiting for the trader to aim it. While one is
  /// set the chart places instead of panning, and the hint strip says what it
  /// wants; clearing it hands the chart back.
  DrawingKind? _armingKind;
  PositionSide? _armingSide;

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

  /// In fullscreen the canvas owns the screen, so the buy/sell bar is collapsed
  /// to one small button until the trader asks for it.
  bool _tradeBarOpen = false;

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

  /// Set when the levels came from a position tool: the box knows its own side,
  /// which may be the opposite of the one the form opened with.
  String? _selectionDirection;

  bool get _isBuy =>
      (_selectionDirection ?? widget.direction).toUpperCase() != 'SELL';

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
    _syncState = widget.debugSyncState ?? ChartSyncState.idle;
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
    if (!mounted) return;
    if (loaded.isNotEmpty) {
      setState(() => _drawings = loaded);
      _rememberVersions(loaded);
    }
    // The device copy paints first; the account copy follows, so a level pinned
    // on the web desk is on the chart without the trader waiting on the network.
    _queueCloudSync();
  }

  /// Persists on every change so a back gesture cannot lose the trader's work.
  void _commitDrawings(List<ChartDrawing> next, {bool keepRedo = false}) {
    setState(() {
      _drawings = next;
      _selectedDrawing = null;
      if (!keepRedo) _redo.clear();
    });
    _persistDrawings(next);
  }

  /// Takes back the last change of any kind — a placed object, a drag, a
  /// restyle, a delete. The whole list is kept, so undo is never approximate.
  void _undo() {
    if (_drawings.isEmpty) return;
    final before = _drawings;
    _commitDrawings(_drawings.sublist(0, _drawings.length - 1), keepRedo: true);
    setState(() => _redo.add(before));
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    final next = _redo.removeLast();
    _commitDrawings(next, keepRedo: true);
  }

  /// Restyles the selected object without touching its geometry.
  void _restyleSelected(
    DrawingLook Function(DrawingLook look) change, {
    bool reselect = true,
  }) {
    final index = _selectedDrawing;
    if (index == null || index >= _drawings.length) return;
    final drawing = _drawings[index];
    final next = [..._drawings];
    next[index] = drawing.withLook(change(drawing.look));
    _commitDrawings(next);
    if (reselect) setState(() => _selectedDrawing = index);
  }

  /// How many points the armed tool needs. A horizontal line, a vertical line
  /// and a text label are one point; everything else is a start and an end.
  int get _placementPoints => switch (_armingKind) {
        DrawingKind.ray ||
        DrawingKind.vline ||
        DrawingKind.text ||
        DrawingKind.arrowUp ||
        DrawingKind.arrowDown =>
          1,
        _ => 2,
      };

  /// Writes the device copy now and schedules the shared one.
  ///
  /// Every path that changes an object ends here, so no edit can reach the phone
  /// and miss the account. The cloud write is debounced: a drag produces a
  /// commit per frame, and only the position the finger was lifted at matters.
  ///
  /// Each object whose content actually changed is stamped with the moment of
  /// the edit. That timestamp is what settles a disagreement with the web desk;
  /// stamping on sync instead would make an edit made hours ago look new just
  /// because the phone had been offline.
  void _persistDrawings(List<ChartDrawing> drawings) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stamped = <ChartDrawing>[];
    final versions = <String, String>{};
    for (final drawing in drawings) {
      final signature = drawingSignature(drawing);
      final key = drawing.id ?? 'new:$signature';
      final untouched = _drawingVersions[key] == signature;
      final next = untouched ? drawing : drawing.withEditedAt(now);
      stamped.add(next);
      versions[key] = signature;
    }
    _drawingVersions
      ..clear()
      ..addAll(versions);
    if (mounted) setState(() => _drawings = stamped);
    unawaited(ChartDrawingStore.save(widget.instrument.symbol, stamped));
    _queueCloudSync();
  }

  /// Records what every object looks like now, so the next persist can tell an
  /// edit from a list that merely passed through untouched.
  void _rememberVersions(List<ChartDrawing> drawings) {
    _drawingVersions
      ..clear()
      ..addEntries([
        for (final drawing in drawings)
          MapEntry(
            drawing.id ?? 'new:${drawingSignature(drawing)}',
            drawingSignature(drawing),
          ),
      ]);
  }

  void _queueCloudSync() {
    if (!_cloudDrawings.available) return;
    // A change made while a reconciliation is in flight would otherwise be
    // dropped with the running call, so it is remembered and replayed once the
    // call returns.
    if (_cloudSyncRunning) _cloudSyncAgain = true;
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = Timer(
      const Duration(milliseconds: 1500),
      () => unawaited(_flushCloudSync()),
    );
  }

  /// Reconciles this chart with `chart_drawings` in both directions.
  ///
  /// A failure is deliberately quiet: the objects on the device are the truth
  /// for this chart, and a share that could not happen must never look like a
  /// lost level.
  Future<void> _clearSharedDrawings() async {
    final error = await _cloudDrawings.clear(widget.instrument.symbol);
    _setSyncOutcome(error);
  }

  /// The account-copy badge, in the app bar or over the fullscreen chart.
  ///
  /// `overlay` is the fullscreen chart, which carries the trader's own chart
  /// theme rather than the app palette, so the badge reads on a black canvas in
  /// the same colours as the tools beside it.
  Widget _syncAction({bool overlay = false}) {
    if (_syncState == ChartSyncState.idle) return const SizedBox.shrink();
    return ChartSyncBadge(
      state: _syncState,
      onExplain: _explainSyncFailure,
      muted: overlay ? _style.muted : null,
      savedInk: overlay ? _style.text : null,
      failedInk: overlay ? _style.bear : null,
    );
  }

  void _explainSyncFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _syncMessage ??
              'This chart could not reach your account. The levels on this '
                  'device are unaffected.',
        ),
      ),
    );
  }

  /// Records a share result. A success fades after a moment, because a badge
  /// that never leaves stops meaning anything; a failure stays until the next
  /// successful sync, because that is the one the trader may need to act on.
  void _setSyncOutcome(String? error) {
    if (!mounted) return;
    _syncHideTimer?.cancel();
    setState(() {
      _syncMessage = error;
      _syncState = error == null ? ChartSyncState.saved : ChartSyncState.failed;
    });
    if (error != null) return;
    _syncHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _syncState != ChartSyncState.saved) return;
      setState(() => _syncState = ChartSyncState.idle);
    });
  }

  Future<void> _flushCloudSync() async {
    if (_cloudSyncRunning || !mounted) return;
    _cloudSyncRunning = true;
    final before = _drawings;
    setState(() => _syncState = ChartSyncState.syncing);
    try {
      final outcome = await _cloudDrawings.sync(
        widget.instrument.symbol,
        before,
      );
      if (!mounted) return;
      _setSyncOutcome(outcome.error);
      if (!outcome.changed || !identical(_drawings, before)) return;
      setState(() => _drawings = outcome.drawings);
      _rememberVersions(outcome.drawings);
      unawaited(
        ChartDrawingStore.save(widget.instrument.symbol, outcome.drawings),
      );
    } catch (_) {
      // The sync handles its own network errors; this is the last line, so the
      // badge can never sit on "syncing" for good.
      _setSyncOutcome(
        'This chart could not reach your account. The levels on this device '
        'are unaffected.',
      );
    } finally {
      _cloudSyncRunning = false;
      if (_cloudSyncAgain) {
        _cloudSyncAgain = false;
        _queueCloudSync();
      }
    }
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
    _persistDrawings(_drawings);
  }

  void _deleteDrawing(int index) {
    if (index < 0 || index >= _drawings.length) return;
    _commitDrawings([..._drawings]..removeAt(index));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _playTimer?.cancel();
    _cloudSyncTimer?.cancel();
    _syncHideTimer?.cancel();
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
      _refreshPeriod,
      (_) => _load(silent: true),
    );
  }

  /// How often the live tail is refetched.
  ///
  /// A third of a bar: soon enough that the newest candle keeps moving, late
  /// enough that a 5-second chart does not turn into a request every second.
  /// Floored at four seconds and capped at a minute, which is what the old fixed
  /// minute became for hourly and daily charts.
  Duration get _refreshPeriod {
    final third = (_interval.size.inMilliseconds / 3).round();
    return Duration(milliseconds: third.clamp(4000, 60000));
  }

  /// A past window never changes, so it is fetched once and not polled.
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Candle sizes the chart feed refused this session, because a server built
  /// before that size existed answers "Unknown candle interval".
  final Set<ChartInterval> _refusedIntervals = {};

  /// True when the error is the feed saying it does not know this candle size,
  /// which is a build question, not a connection one.
  bool _unknownInterval(Object error) =>
      error is MarketDataException &&
      error.message.toLowerCase().contains('unknown candle interval');

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
      final previousClose = _candles.isEmpty ? null : _candles.last.close;
      setState(() {
        _candles = candles;
        _loading = false;
        _error = null;
        _staleAt = null;
        _updated = DateTime.now();
      });
      _checkLevelTouches(previousClose, candles);
    } catch (error) {
      if (!mounted) return;
      // A failed background refresh must not wipe a chart the trader can use.
      if (silent && _candles.isNotEmpty) return;
      // A size the deployed feed has never heard of is not a dead end. Drop to
      // one minute, which every build has served, say so once, and remember the
      // refusal so the picker stops offering a choice that cannot work.
      if (_unknownInterval(error) && !_refusedIntervals.contains(_interval)) {
        final refused = _interval;
        _refusedIntervals.add(refused);
        if (refused != ChartInterval.oneMinute) {
          setState(() {
            _interval = ChartInterval.oneMinute;
            _loading = true;
            _error = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${refused.key.toUpperCase()} candles are not served by this '
                'chart feed yet — showing 1M.',
              ),
            ),
          );
          await _load(force: true);
          return;
        }
      }
      // With nothing in memory and the feed refusing, stand on the last market
      // this device actually saw. It is stamped everywhere it is shown, so an
      // old chart can never be mistaken for a live one.
      if (_candles.isEmpty && !_customWindow) {
        final offline = await _market.offline(widget.instrument, _interval);
        if (!mounted) return;
        if (offline != null && offline.candles.isNotEmpty) {
          setState(() {
            _candles = offline.candles;
            _loading = false;
            _error = null;
            _staleAt = offline.at;
            _updated = offline.at;
          });
          return;
        }
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  /// When each level was last reported, so a price that hovers around a level
  /// does not produce an alert on every poll.
  final Map<String, DateTime> _touchedAt = {};

  /// Tells the trader when price crosses a level they marked.
  ///
  /// The comparison is previous close against new close, so one crossing is one
  /// alert. Levels come from the position tool and from every horizontal ray; a
  /// hidden object still counts, because hiding a level is about what the chart
  /// draws, not about what the trader is watching for.
  void _checkLevelTouches(double? previousClose, List<Candle> candles) {
    if (previousClose == null || candles.isEmpty) return;
    final levels = <WatchedLevel>[];
    void add(String label, double? price) {
      if (price == null || !price.isFinite) return;
      levels.add(WatchedLevel(label: label, price: price));
    }

    add('entry', _entry);
    add('stop', _stop);
    add('target', _take);
    add('exit', _exit);
    for (final drawing in _drawings) {
      if (drawing.kind == DrawingKind.ray) add('level', drawing.price);
    }
    if (levels.isEmpty) return;

    final close = candles.last.close;
    final now = DateTime.now();
    for (final hit in touchedLevels(
      from: previousClose,
      to: close,
      levels: levels,
    )) {
      final key = '${widget.instrument.symbol}|${hit.label}|${hit.price}';
      final last = _touchedAt[key];
      if (last != null && now.difference(last) < const Duration(minutes: 5)) {
        continue;
      }
      _touchedAt[key] = now;
      unawaited(
        Alerts.instance.levelTouched(
          symbol: widget.instrument.symbol,
          label: hit.label,
          price: hit.price,
          crossedFrom: previousClose,
          crossedTo: close,
          decimals: widget.instrument.decimals,
        ),
      );
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
    // Turning the phone sideways is a request, not a coincidence: it is how a
    // trader asks for the analysis view. Landscape therefore opens the chart on
    // its own, with the controls moved to a rail so the candles get the whole
    // screen, and everything needed is still one tap away.
    final landscape =
        MediaQuery.maybeOrientationOf(context) == Orientation.landscape;
    return PopScope(
      // Back leaves the fullscreen canvas instead of the chart screen.
      canPop: !_fullscreen && !landscape,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_fullscreen) {
          _toggleFullscreen();
          return;
        }
        // Landscape hides the app bar, so back is the way out of the screen.
        if (landscape) Navigator.of(context).maybePop();
      },
      child: landscape
          ? _landscapeView()
          : (_fullscreen ? _fullscreenView() : _screenView()),
    );
  }

  /// The analysis posture: chart edge to edge, one narrow rail for the tools,
  /// and the two things a trader glances at — price and interval — floating on
  /// the canvas they belong to.
  Widget _landscapeView() {
    return Scaffold(
      backgroundColor: _style.background,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _chartPanel(widget.instrument, expand: true),
                  ),
                  Positioned(
                    left: 6,
                    top: 4,
                    right: 6,
                    child: _landscapeReadout(),
                  ),
                  if (_replay != null)
                    Positioned(
                      left: 6,
                      top: 40,
                      right: 6,
                      child: _replayStrip(overlay: true),
                    ),
                  if (_tradeBarOpen)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ColoredBox(
                        color: _style.background.withAlpha(242),
                        child: _tradeBar(compact: true),
                      ),
                    ),
                ],
              ),
            ),
            _landscapeRail(),
          ],
        ),
      ),
    );
  }

  /// Symbol, last price, the day's change and the interval, in the corner of the
  /// canvas where a desk sweeps its legend. It carries the way out too, because
  /// landscape has no app bar.
  Widget _landscapeReadout() {
    final instrument = widget.instrument;
    final last = _lastVisible?.close;
    final change = _changePercent;
    final up = (change ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _style.background.withAlpha(200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.arrow_back, size: 16, color: _style.muted),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            instrument.symbol,
            style: TextStyle(
              color: _style.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          if (last != null) ...[
            const SizedBox(width: 6),
            Text(
              chartPrice(last, instrument),
              style: tabular.copyWith(
                color: _style.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (change != null) ...[
            const SizedBox(width: 5),
            Text(
              '${up ? '+' : ''}${change.toStringAsFixed(2)}%',
              style: tabular.copyWith(
                color: up ? _style.bull : _style.bear,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _style.axis.withAlpha(120),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _interval.key,
              style: tabular.copyWith(
                color: _style.text,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          _syncAction(overlay: true),
        ],
      ),
    );
  }

  /// The tools column: the same set the portrait header offers, stacked where
  /// they cost width the chart has to spare rather than height it does not.
  Widget _landscapeRail() {
    Widget button({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onTap,
      bool active = false,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 19,
          color: active
              ? AppColors.primaryLight
              : (onTap == null ? _style.axis : _style.muted),
        ),
      );
    }

    return Container(
      width: 46,
      decoration: BoxDecoration(
        color: _style.background,
        border: Border(left: BorderSide(color: _style.axis, width: 0.8)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          button(
            icon: Icons.draw_outlined,
            tooltip: 'Drawing tools',
            onTap: _openDrawingTools,
            active: _armingKind != null || _armingSide != null,
          ),
          button(
            icon: Icons.timer_outlined,
            tooltip: 'Time frame',
            onTap: _openTimeFrameSheet,
          ),
          button(
            icon: Icons.replay,
            tooltip: 'Market replay',
            onTap: _candles.length < 12 ? null : _toggleReplayMode,
            active: _replay != null,
          ),
          button(
            icon: Icons.hdr_strong,
            tooltip: _magnet ? 'Magnet on' : 'Magnet off',
            onTap: () => setState(() => _magnet = !_magnet),
            active: _magnet,
          ),
          button(
            icon: Icons.tune,
            tooltip: 'Chart style',
            onTap: _openStyleSheet,
          ),
          const Spacer(),
          button(
            icon: _tradeBarOpen ? Icons.close : Icons.swap_vert,
            tooltip: _tradeBarOpen ? 'Hide buy and sell' : 'Buy / sell',
            onTap: _activePosition() == null
                ? null
                : () => setState(() => _tradeBarOpen = !_tradeBarOpen),
            active: _tradeBarOpen,
          ),
          const SizedBox(height: 2),
        ],
      ),
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
            onPressed: _openDrawingTools,
            icon: Icon(Icons.draw_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Market replay',
            onPressed: _candles.length < 12 ? null : _toggleReplayMode,
            icon: Icon(Icons.replay, size: 20),
          ),
          IconButton(
            tooltip: 'Chart style',
            onPressed: _openStyleSheet,
            icon: Icon(Icons.tune, size: 20),
          ),
          // A break between the tools that change the chart and the one that
          // only changes how it fills the screen. Clearing the levels lives in
          // the Levels card now, where the levels are, instead of sitting
          // next to fullscreen under the same finger.
          _syncAction(),
          IconButton(
            tooltip: _magnet ? 'Magnet on' : 'Magnet off',
            onPressed: () => setState(() => _magnet = !_magnet),
            icon: Icon(
              Icons.hdr_strong,
              size: 20,
              color: _magnet ? AppColors.primaryLight : AppColors.muted,
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: AppColors.border,
          ),
          IconButton(
            tooltip: 'Fullscreen',
            onPressed: _candles.isEmpty ? null : _toggleFullscreen,
            icon: Icon(Icons.fullscreen, size: 21),
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
                      _tradeBar(),
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
            if (_tradeBarOpen) _tradeBar(compact: true),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            tooltip: 'Chart tools',
            onPressed: _openDrawingTools,
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
          // The same badge as the app bar: fullscreen hides the bar, and a level
          // that did not reach the account is exactly what a trader must not
          // discover after leaving the canvas.
          _syncAction(overlay: true),
          IconButton(
            tooltip: _magnet ? 'Magnet on' : 'Magnet off',
            onPressed: () => setState(() => _magnet = !_magnet),
            icon: Icon(
              Icons.hdr_strong,
              size: 19,
              color: _magnet ? _style.text : _style.muted,
            ),
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
              _tradeToggle(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drag a level line to move it and its time',
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

  /// The one small button that stands in for the buy/sell bar in fullscreen.
  ///
  /// The canvas is the reason for fullscreen, so the two sides are folded away
  /// behind a single tap and come back at 32px instead of 46px.
  Widget _tradeToggle() {
    final ready = _activePosition() != null && !_loading && _error == null;
    final open = _tradeBarOpen;
    final ink = open ? AppColors.primaryLight : _style.muted;
    return Semantics(
      button: true,
      label: open ? 'Hide buy and sell' : 'Show buy and sell',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: ready ? () => setState(() => _tradeBarOpen = !open) : null,
        child: Opacity(
          opacity: ready ? 1 : 0.4,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: _style.background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: open ? AppColors.primary : _style.axis,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(open ? Icons.close : Icons.swap_vert, size: 15, color: ink),
                const SizedBox(width: 5),
                Text(
                  open ? 'Hide' : 'Buy / sell',
                  style: TextStyle(
                    color: ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final canvas = _ChartCanvas(
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
      onLevelMoved: _levelMoved,
      drawings: _drawings,
      selectedDrawing: _selectedDrawing,
      onDrawingTapped: _openDrawingActions,
      // Resolved once per build, not per frame: the canvas repaints on every
      // pan, and the first-touch scan does not depend on the viewport.
      positionOutcomes: [
        for (final drawing in _drawings)
          drawing.isPosition
              ? resolvePositionOutcome(
                  drawing: drawing,
                  candles: _visibleCandles,
                )
              : null,
      ],
      onDrawingSelected: (index) => setState(() => _selectedDrawing = index),
      onDrawingMoved: _moveDrawing,
      onDrawingMoveEnd: _finishDrawingMove,
      onReachStart: _loadingOlder ? null : _loadOlder,
      pendingKind: _armingKind,
      pendingSide: _armingSide,
      magnet: _magnet,
      onCrosshair: (candle) {
        if (identical(candle, _hover)) return;
        setState(() => _hover = candle);
      },
      onPlacing: (down) {
        if (down == _placing) return;
        setState(() => _placing = down);
      },
      onDrawingCreated: (drawing) => unawaited(_placeDrawing(drawing)),
    );

    final armed = _armingKind != null || _armingSide != null;
    final selected = _selectedDrawing;
    final showBar = selected != null &&
        selected < _drawings.length &&
        !armed &&
        !_drawings[selected].look.locked;
    if (!armed && !showBar) return canvas;
    // The banners sit above the chart rather than floating over it, so they can
    // never cover the candles the object is being aimed at.
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (armed) _placementBanner(),
        if (showBar) _objectBar(selected),
        if (expand) Expanded(child: canvas) else canvas,
      ],
    );
  }

  /// The placement banner, as TradingView draws it: how far through the object
  /// the finger is on the left, what to do next in the middle, and a bin on the
  /// right to walk away from the tool.
  Widget _placementBanner() {
    final total = _placementPoints;
    final placed = _placing ? total : 1;
    final title = _placing
        ? (total > 1 ? 'Lift to finish up' : 'Lift to place')
        : (total > 1 ? 'Tap or drag to place' : 'Tap to place');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF111417),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: drawingColor.withAlpha(70)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: drawingColor.withAlpha(38),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$placed of $total',
              style: tabular.copyWith(
                color: drawingColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF2F4F7),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Put the tool away',
            onPressed: _disarmTool,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Color(0xFFF2F4F7),
            ),
          ),
        ],
      ),
    );
  }

  /// The selected object's own toolbar, the way a desk swaps its tool row for
  /// the object it is holding: clone, colour, weight, line style and remove,
  /// with everything else behind the overflow.
  Widget _objectBar(int index) {
    final drawing = _drawings[index];
    final look = drawing.look;
    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onTap,
      bool active = false,
      Color? tone,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 18,
          color: onTap == null
              ? AppColors.faint
              : (tone ?? (active ? drawingColor : AppColors.muted)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      height: 38,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            alignment: Alignment.center,
            child: Icon(Icons.drag_indicator, size: 14, color: AppColors.faint),
          ),
          Expanded(
            child: Text(
              _drawingTitle(drawing),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          action(
            icon: Icons.copy_all_outlined,
            tooltip: 'Clone',
            onTap: () => _cloneDrawing(index),
          ),
          action(
            icon: Icons.palette_outlined,
            tooltip: 'Colour',
            active: look.tint != null,
            onTap: () => unawaited(
              _pickCustomColor(
                _drawingTitle(drawing),
                look.tint ?? drawingColor,
                (picked) => _restyleSelected(
                  (current) => current.copyWith(tint: picked),
                ),
              ),
            ),
          ),
          action(
            icon: Icons.line_weight,
            tooltip: 'Line width',
            active: look.weight != null,
            onTap: () {
              // 1, 2, 3 and back to the chart's own weight.
              final nextWeight = switch (look.weight) {
                null => 2.0,
                2.0 => 3.0,
                3.0 => null,
                _ => 1.0,
              };
              _restyleSelected(
                (current) => nextWeight == null
                    ? current.copyWith(clearWeight: true)
                    : current.copyWith(weight: nextWeight),
              );
            },
          ),
          action(
            icon: Icons.more_horiz,
            tooltip: 'Line style',
            active: look.dashed,
            onTap: () => _restyleSelected(
              (current) => current.copyWith(dashed: !current.dashed),
            ),
          ),
          action(
            icon: Icons.lock_outline,
            tooltip: 'Lock',
            onTap: () => _restyleSelected(
              (current) => current.copyWith(locked: true),
              reselect: false,
            ),
          ),
          action(
            icon: Icons.delete_outline,
            tooltip: 'Remove',
            tone: AppColors.danger,
            onTap: () => _deleteDrawing(index),
          ),
        ],
      ),
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
        // A fetched window is the feed's own read, whatever was on screen
        // before it.
        _staleAt = null;
      });
      return candles;
    } catch (error) {
      if (!mounted) return null;
      // The day the trader jumped to may already be on this phone from an
      // earlier visit: stand on it and say when it was fetched.
      final copy = await _market.offline(
        widget.instrument,
        _interval,
        from: start,
        to: end,
      );
      if (!mounted) return null;
      if (copy != null) {
        setState(() {
          _candles = copy.candles;
          _loading = false;
          _error = null;
          _staleAt = copy.at;
          _updated = copy.at;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Feed down — showing this window from the copy saved '
              '${DateFormat('EEE HH:mm').format(copy.at)}.',
            ),
          ),
        );
        return copy.candles;
      }
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
      // Panning into history the phone already holds is not a failure, even
      // with the feed down.
      final copy = await _market.offline(
        widget.instrument,
        _interval,
        from: oldest.subtract(_rangeSpan),
        to: oldest,
      );
      if (!mounted) return;
      if (copy != null) {
        final fresh = copy.candles
            .where((candle) => candle.time.isBefore(oldest))
            .toList();
        if (fresh.isNotEmpty) {
          setState(() {
            _candles = [...fresh, ..._candles];
            _replay = ReplayCursor(
              count: _candles.length,
              index: replay.index + fresh.length,
            );
            _staleAt = copy.at;
          });
          return;
        }
      }
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

  /// The tools hub, laid out like TradingView's analysis panel: the objects
  /// first, then what can be done to the one that is selected.
  ///
  /// Tools no longer arm a tap. Choosing one places the object on the chart
  /// immediately and the trader drags it into place — which is what stops a
  /// stray tap on the chart from starting a point.
  Future<void> _openDrawingTools() async {
    final selected = _selectedDrawing;
    final hasSelection =
        selected != null && selected >= 0 && selected < _drawings.length;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (sheetContext) {
        void pick(String value) => Navigator.of(sheetContext).pop(value);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Chart tools',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => pick('close'),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Pick a tool and it lands on the chart — drag it to calibrate '
                  'the levels. Tap any object for edit, clone or delete.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                DrawingsPanel(onPick: pick),
                if (hasSelection) ...[
                  const SizedBox(height: 14),
                  _sheetLabel('SELECTED OBJECT'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _toolCard(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          subtitle: 'Set levels',
                          onTap: () => pick('edit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _toolCard(
                          icon: Icons.copy_all_outlined,
                          label: 'Clone',
                          subtitle: 'Copy it',
                          onTap: () => pick('clone'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _toolCard(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          subtitle: 'Remove',
                          tone: AppColors.danger,
                          onTap: () => pick('delete'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                _sheetLabel('MANAGE'),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.undo, size: 20),
                  title: const Text('Undo last change'),
                  enabled: _drawings.isNotEmpty,
                  onTap: () => pick('undo'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.redo, size: 20),
                  title: const Text('Redo'),
                  enabled: _redo.isNotEmpty,
                  onTap: () => pick('redo'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_tree_outlined, size: 20),
                  title: const Text('Object tree'),
                  enabled: _drawings.isNotEmpty,
                  onTap: () => pick('tree'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_sweep_outlined, size: 20),
                  title: const Text('Clear all drawings'),
                  enabled: _drawings.isNotEmpty,
                  onTap: () => pick('clear'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null || action == 'close') return;
    // The position tools arm like every other tool: the entry lands where the
    // trader presses, and the drag sets how far forward the box runs.
    if (action == 'long') {
      _armTool(DrawingKind.position, side: PositionSide.long);
      return;
    }
    if (action == 'short') {
      _armTool(DrawingKind.position, side: PositionSide.short);
      return;
    }
    if (action == 'trend') {
      _armTool(DrawingKind.trend);
      return;
    }
    if (action == 'ray') {
      _armTool(DrawingKind.ray);
      return;
    }
    final objectKind = _objectKindFor(action);
    if (objectKind != null) {
      _armTool(objectKind);
      return;
    }
    if (action == 'undo') {
      _undo();
      return;
    }
    if (action == 'redo') {
      _redoLast();
      return;
    }
    if (action == 'tree') {
      await _openObjectTree();
      return;
    }
    if (action == 'clear') {
      _commitDrawings(const []);
      // The account copy goes too, so a level pinned on the web desk cannot
      // reappear the moment the next sync runs.
      unawaited(_clearSharedDrawings());
      return;
    }
    if (!hasSelection) return;
    if (action == 'edit') {
      await _editDrawing(selected);
      return;
    }
    if (action == 'clone') {
      _cloneDrawing(selected);
      return;
    }
    if (action == 'delete') _deleteDrawing(selected);
  }

  /// One tile in the tools hub: an icon, a name and what it does.
  Widget _toolCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? tone,
  }) {
    final color = tone ?? AppColors.text;
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 21, color: color),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: 9,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetLabel(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.faint,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      );

  /// A starting stop distance for a new position tool: two average candle
  /// ranges, floored so a quiet five-minute chart still gets a visible box, and
  /// capped so one spike cannot put the stop half a screen away.
  double _defaultRisk(double price) {
    if (_candles.isEmpty) return price * 0.005;
    final recent = _candles.length > 40
        ? _candles.sublist(_candles.length - 40)
        : _candles;
    var range = 0.0;
    for (final candle in recent) {
      range += candle.high - candle.low;
    }
    final average = range / recent.length;
    return (average * 2).clamp(price * 0.0005, price * 0.03).toDouble();
  }

  /// Arms a tool and waits for the trader to say where it goes.
  ///
  /// Every tool used to place its own object at a spot the app chose — the last
  /// two dozen candles — which meant the first thing anyone did with a shape was
  /// drag it out of the way. Aiming first is how every desk works: pick the
  /// tool, then put it where it belongs. The canvas shows the object growing
  /// under the finger, so the size is decided before it is committed.
  void _armTool(DrawingKind kind, {PositionSide? side}) {
    setState(() {
      _armingKind = kind;
      _armingSide = side;
      _selectedDrawing = null;
    });
  }

  void _disarmTool() {
    if (_armingKind == null && _armingSide == null) return;
    setState(() {
      _armingKind = null;
      _armingSide = null;
      _placing = false;
    });
  }

  /// An object the trader has placed. Text asks for its words afterwards, so the
  /// label lands where they pointed rather than in the middle of the chart, and
  /// it is not created at all if they back out of the dialog.
  Future<void> _placeDrawing(ChartDrawing drawing) async {
    _disarmTool();
    if (drawing.kind == DrawingKind.text) {
      final words = await _askWords();
      if (!mounted || words == null || words.isEmpty) return;
      _addDrawing(
        ChartDrawing.points(
          kind: DrawingKind.text,
          text: words,
          points: drawing.points,
        ),
      );
      return;
    }
    _addDrawing(drawing);
  }

  Future<String?> _askWords() async {
    final controller = TextEditingController();
    final words = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Text',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: TextStyle(color: AppColors.text, fontSize: 13),
          decoration: const InputDecoration(hintText: 'Note on the chart'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted) return null;
    return words;
  }

  /// Maps the sheet's tool id onto the object it creates.
  DrawingKind? _objectKindFor(String id) {
    switch (id) {
      case 'vline':
        return DrawingKind.vline;
      case 'rectangle':
        return DrawingKind.rectangle;
      case 'ellipse':
        return DrawingKind.ellipse;
      case 'fib':
        return DrawingKind.fib;
      case 'fibExtension':
        return DrawingKind.fibExtension;
      case 'measure':
        return DrawingKind.measure;
      case 'text':
        return DrawingKind.text;
      case 'arrowUp':
        return DrawingKind.arrowUp;
      case 'arrowDown':
        return DrawingKind.arrowDown;
      case 'brush':
        return DrawingKind.brush;
    }
    return null;
  }

  /// Adds a drawing and selects it, so its handles are visible without a
  /// second tap — the levels are the point of the tool.
  void _addDrawing(ChartDrawing drawing) {
    final next = [..._drawings, drawing];
    setState(() {
      _drawings = next;
      _selectedDrawing = next.length - 1;
    });
    _persistDrawings(next);
  }

  /// Copies a drawing, nudged a fraction of its own risk so the copy is visible
  /// next to the original instead of hidden under it.
  void _cloneDrawing(int index) {
    if (index < 0 || index >= _drawings.length) return;
    final source = _drawings[index];
    final last = _lastVisible;
    final base = last?.close ?? source.entry ?? source.startPrice;
    final nudge = _defaultRisk(base) * 0.3;

    final copy = switch (source.kind) {
      DrawingKind.ray =>
        ChartDrawing.ray(price: (source.price ?? base) + nudge),
      DrawingKind.trend => ChartDrawing.trend(
          startMs: source.startMs,
          startPrice: source.startPrice + nudge,
          endMs: source.endMs,
          endPrice: source.endPrice + nudge,
        ),
      DrawingKind.position => ChartDrawing.position(
          side: source.side ?? PositionSide.long,
          startMs: source.startMs,
          endMs: source.endMs,
          entry: (source.entry ?? base) + nudge,
          stop: (source.stop ?? base) + nudge,
          target: (source.target ?? base) + nudge,
        ),
      _ => ChartDrawing.points(
          kind: source.kind,
          text: source.text,
          points: [
            for (final point in source.points)
              ChartPoint(ms: point.ms, price: point.price + nudge),
          ],
        ),
    };
    _addDrawing(copy);
  }

  String _drawingTitle(ChartDrawing drawing) {
    switch (drawing.kind) {
      case DrawingKind.ray:
        return 'Horizontal ray';
      case DrawingKind.trend:
        return 'Trend line';
      case DrawingKind.position:
        return drawing.side == PositionSide.short
            ? 'Short position'
            : 'Long position';
      case DrawingKind.rectangle:
        return 'Rectangle';
      case DrawingKind.ellipse:
        return 'Ellipse';
      case DrawingKind.vline:
        return 'Vertical line';
      case DrawingKind.fib:
        return 'Fib retracement';
      case DrawingKind.fibExtension:
        return 'Fib extension';
      case DrawingKind.text:
        return drawing.text == null ? 'Text' : 'Text — ${drawing.text}';
      case DrawingKind.arrowUp:
        return 'Arrow up';
      case DrawingKind.arrowDown:
        return 'Arrow down';
      case DrawingKind.brush:
        return 'Brush';
      case DrawingKind.measure:
        return 'Measure';
    }
  }

  String _positionSummary(ChartDrawing drawing) {
    final decimals = widget.instrument.decimals;
    final entry = drawing.entry;
    final stop = drawing.stop;
    final target = drawing.target;
    final risk = drawing.rewardRatio;
    String fmt(double? value) =>
        value == null ? '—' : value.toStringAsFixed(decimals);
    return 'Entry ${fmt(entry)} · Stop ${fmt(stop)} · Target ${fmt(target)}'
        '${risk == null ? '' : ' · ${risk.toStringAsFixed(1)}R'}';
  }

  /// What tapping an object offers: TradingView's edit, clone and delete.
  Future<void> _openDrawingActions(int index) async {
    if (index < 0 || index >= _drawings.length) return;
    final drawing = _drawings[index];
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _drawingTitle(drawing),
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              if (drawing.isPosition) ...[
                Text(
                  _positionSummary(drawing),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: _toolCard(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      subtitle: 'Set levels',
                      onTap: () => Navigator.of(sheetContext).pop('edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _toolCard(
                      icon: Icons.copy_all_outlined,
                      label: 'Clone',
                      subtitle: 'Copy it',
                      onTap: () => Navigator.of(sheetContext).pop('clone'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _toolCard(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      subtitle: 'Remove',
                      tone: AppColors.danger,
                      onTap: () => Navigator.of(sheetContext).pop('delete'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The rest of the object menu, where TradingView keeps it: the
              // switches that decide whether this object can be touched or seen,
              // and the door to every other object on the chart.
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  drawing.look.locked ? Icons.lock : Icons.lock_open,
                  size: 19,
                ),
                title: Text(drawing.look.locked ? 'Unlock' : 'Lock'),
                subtitle: Text(
                  drawing.look.locked
                      ? 'Let the finger move it again'
                      : 'Hold it exactly where it is',
                ),
                onTap: () => Navigator.of(sheetContext).pop('lock'),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.visibility_off_outlined, size: 19),
                title: const Text('Hide'),
                subtitle: const Text('Clear it off the chart, keep the idea'),
                onTap: () => Navigator.of(sheetContext).pop('hide'),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_tree_outlined, size: 19),
                title: const Text('Object tree'),
                subtitle: Text('${_drawings.length} objects on this chart'),
                onTap: () => Navigator.of(sheetContext).pop('tree'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editDrawing(index);
      return;
    }
    if (action == 'clone') {
      _cloneDrawing(index);
      return;
    }
    if (action == 'delete') {
      _deleteDrawing(index);
      return;
    }
    if (action == 'lock') {
      final next = [..._drawings];
      next[index] = drawing.withLook(
        drawing.look.copyWith(locked: !drawing.look.locked),
      );
      _commitDrawings(next);
      return;
    }
    if (action == 'hide') {
      final next = [..._drawings];
      next[index] = drawing.withLook(drawing.look.copyWith(hidden: true));
      _commitDrawings(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Object hidden.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (!mounted) return;
              final restore = [..._drawings];
              final at = restore.indexWhere(
                (item) => item.id == drawing.id &&
                    item.kind == drawing.kind &&
                    item.look.hidden,
              );
              if (at < 0) return;
              restore[at] = restore[at].withLook(
                restore[at].look.copyWith(hidden: false),
              );
              _commitDrawings(restore);
            },
          ),
        ),
      );
      return;
    }
    if (action == 'tree') {
      await _openObjectTree();
    }
  }

  /// Every object on this chart, visible or not: tap one to select it on the
  /// canvas, or flip its eye and lock from here. TradingView's object tree is
  /// the only place a hidden object can be found again.
  Future<void> _openObjectTree() async {
    if (_drawings.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void update(int index, DrawingLook Function(DrawingLook) change) {
              final next = [..._drawings];
              next[index] = next[index].withLook(change(next[index].look));
              _commitDrawings(next);
              setSheetState(() {});
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Object tree',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _drawings.length,
                        itemBuilder: (context, index) {
                          final item = _drawings[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              item.look.hidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 19,
                              color: item.look.hidden
                                  ? AppColors.faint
                                  : item.ink,
                            ),
                            title: Text(
                              _drawingTitle(item),
                              style: TextStyle(
                                color: item.look.hidden
                                    ? AppColors.muted
                                    : AppColors.text,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: item.isPosition
                                ? Text(
                                    _positionSummary(item),
                                    style: TextStyle(
                                      color: AppColors.faint,
                                      fontSize: 10.5,
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              setState(() => _selectedDrawing = index);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: item.look.locked
                                      ? 'Unlock'
                                      : 'Lock',
                                  onPressed: () => update(
                                    index,
                                    (look) =>
                                        look.copyWith(locked: !look.locked),
                                  ),
                                  icon: Icon(
                                    item.look.locked
                                        ? Icons.lock
                                        : Icons.lock_open,
                                    size: 17,
                                    color: item.look.locked
                                        ? drawingColor
                                        : AppColors.faint,
                                  ),
                                ),
                                IconButton(
                                  tooltip: item.look.hidden ? 'Show' : 'Hide',
                                  onPressed: () => update(
                                    index,
                                    (look) =>
                                        look.copyWith(hidden: !look.hidden),
                                  ),
                                  icon: Icon(
                                    item.look.hidden
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 17,
                                    color: AppColors.faint,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The object's settings: its prices, and for a position its side. Times are
  /// still moved by dragging on the chart, where they can be seen against the
  /// candles.
  Future<void> _editDrawing(int index) async {
    if (index < 0 || index >= _drawings.length) return;
    final drawing = _drawings[index];
    final decimals = widget.instrument.decimals;
    String fmt(double value) => value.toStringAsFixed(decimals);

    final priceFields = <String, TextEditingController>{};
    if (drawing.kind == DrawingKind.ray) {
      priceFields['Price'] = TextEditingController(
        text: fmt(drawing.price ?? 0),
      );
    } else if (drawing.isPosition) {
      priceFields['Entry'] = TextEditingController(
        text: fmt(drawing.entry ?? 0),
      );
      priceFields['Stop'] = TextEditingController(
        text: fmt(drawing.stop ?? 0),
      );
      priceFields['Target'] = TextEditingController(
        text: fmt(drawing.target ?? 0),
      );
    } else {
      priceFields['Start price'] = TextEditingController(
        text: fmt(drawing.startPrice),
      );
      priceFields['End price'] = TextEditingController(
        text: fmt(drawing.endPrice),
      );
    }
    var side = drawing.side ?? PositionSide.long;

    double read(String label, double fallback) {
      final raw = priceFields[label]?.text.trim() ?? '';
      final value = double.tryParse(raw);
      return value == null || value <= 0 ? fallback : value;
    }

    final edited = await showModalBottomSheet<ChartDrawing>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void flip(PositionSide next) {
              if (next == side) return;
              side = next;
              // Flipping the side mirrors the levels, so the box keeps the same
              // risk and reward instead of pointing the stop and target the
              // wrong way round.
              final mirrored = drawing.withSide(next);
              if (mirrored.entry != null) {
                priceFields['Entry']!.text = fmt(mirrored.entry!);
              }
              if (mirrored.stop != null) {
                priceFields['Stop']!.text = fmt(mirrored.stop!);
              }
              if (mirrored.target != null) {
                priceFields['Target']!.text = fmt(mirrored.target!);
              }
              setSheetState(() {});
            }

            ChartDrawing build() {
              // Every rebuild carries the row id, so retyping a level updates
              // the shared object instead of leaving the old one behind.
              if (drawing.kind == DrawingKind.ray) {
                return ChartDrawing.ray(
                  id: drawing.id,
                  look: drawing.look,
                  price: read('Price', drawing.price ?? 0),
                );
              }
              if (drawing.isPosition) {
                return ChartDrawing.position(
                  id: drawing.id,
                  look: drawing.look,
                  side: side,
                  startMs: drawing.startMs,
                  endMs: drawing.endMs,
                  entry: read('Entry', drawing.entry ?? 0),
                  stop: read('Stop', drawing.stop ?? 0),
                  target: read('Target', drawing.target ?? 0),
                );
              }
              return ChartDrawing.trend(
                id: drawing.id,
                look: drawing.look,
                startMs: drawing.startMs,
                startPrice: read('Start price', drawing.startPrice),
                endMs: drawing.endMs,
                endPrice: read('End price', drawing.endPrice),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit ${_drawingTitle(drawing).toLowerCase()}',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (drawing.isPosition) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _sideChip(
                                label: 'Long',
                                selected: side == PositionSide.long,
                                color: AppColors.success,
                                onTap: () => flip(PositionSide.long),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _sideChip(
                                label: 'Short',
                                selected: side == PositionSide.short,
                                color: AppColors.danger,
                                onTap: () => flip(PositionSide.short),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final field in priceFields.entries) ...[
                        Text(
                          field.key,
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: field.value,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'Times are moved by dragging the object on the chart.',
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(build()),
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    for (final controller in priceFields.values) {
      controller.dispose();
    }
    if (edited == null || !mounted) return;
    final next = [..._drawings];
    next[index] = edited;
    setState(() {
      _drawings = next;
      _selectedDrawing = index;
    });
    _persistDrawings(next);
  }

  Widget _sideChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color.withAlpha(38) : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  /// The position tool the BUY/SELL buttons act on: the selected box, or the
  /// most recent one when nothing is selected.
  ({int index, ChartDrawing drawing})? _activePosition() {
    final selected = _selectedDrawing;
    if (selected != null &&
        selected >= 0 &&
        selected < _drawings.length &&
        _drawings[selected].isPosition) {
      return (index: selected, drawing: _drawings[selected]);
    }
    for (var i = _drawings.length - 1; i >= 0; i--) {
      if (_drawings[i].isPosition) return (index: i, drawing: _drawings[i]);
    }
    return null;
  }

  /// BUY or SELL: points the calibration the way the button says and carries
  /// its entry, stop and target into the trade form.
  Future<void> _tradeFromDrawing(PositionSide side) async {
    final active = _activePosition();
    if (active == null) return;
    final drawing = active.drawing.withSide(side);
    final next = [..._drawings];
    next[active.index] = drawing;
    setState(() {
      _drawings = next;
      _selectedDrawing = active.index;
      _entry = drawing.entry;
      _stop = drawing.stop;
      _take = drawing.target;
      _entryTime = DateTime.fromMillisecondsSinceEpoch(
        drawing.startMs,
        isUtc: true,
      );
      _selectionDirection = side == PositionSide.short ? 'SELL' : 'BUY';
    });
    _persistDrawings(next);
    await _confirmLevels();
  }

  /// The BUY / SELL bar that sits under the chart.
  ///
  /// Docked rather than floating: a button over the candles hid the bars it was
  /// meant to trade and sat under the thumb while panning. Full width keeps the
  /// tap that turns a calibration into a trade the largest target on screen.
  Widget _tradeBar({bool compact = false}) {
    final active = _activePosition();
    final ready = active != null && !_loading && _error == null;
    final price = active?.drawing.entry;
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
          : const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: _style.background,
        border: Border(top: BorderSide(color: _style.grid.withAlpha(110))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tradeButton(
              label: 'SELL',
              price: price,
              color: AppColors.danger,
              enabled: ready,
              compact: compact,
              onTap: () => _tradeFromDrawing(PositionSide.short),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tradeButton(
              label: 'BUY',
              price: price,
              color: AppColors.success,
              enabled: ready,
              compact: compact,
              onTap: () => _tradeFromDrawing(PositionSide.long),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tradeButton({
    required String label,
    required double? price,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    final decimals = widget.instrument.decimals;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.field),
          onTap: enabled ? onTap : null,
          child: Container(
            height: compact ? 32 : 46,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: compact ? 11.5 : 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (price != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      price.toStringAsFixed(decimals),
                      style: TextStyle(
                        color: AppColors.ink.withAlpha(180),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleFullscreen() {
    final next = !_fullscreen;
    setState(() {
      _fullscreen = next;
      // Leaving fullscreen restores the normal layout, and the bar there is
      // always visible, so the toggle starts closed again next time.
      _tradeBarOpen = false;
    });
    SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Picks the clock the chart is drawn in. The device clock is the default;
  /// every IANA zone the bundled database knows is searchable.
  Future<ChartZone?> _pickZone(ChartZone current) {
    return showModalBottomSheet<ChartZone>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ZoneSheet(current: current),
    );
  }

  Future<void> _openStyleSheet() async {
    var page = _SettingsPage.home;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.92,
          child: StatefulBuilder(
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
                page: page,
                onNavigate: (next) => setSheetState(() => page = next),
                onClose: () => Navigator.of(context).pop(),
              );
            },
          ),
        );
      },
    );
  }

  /// The chart settings sheet, laid out the way TradingView does it: a short
  /// list of groups that open into a page of their own, every row naming the
  /// setting with its live value on the right. The previous sheet was one long
  /// scroll of switches, so finding a setting meant hunting by feel; the group
  /// list is the map.
  Widget _styleSheet(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged, {
    required _SettingsPage page,
    required ValueChanged<_SettingsPage> onNavigate,
    required VoidCallback onClose,
  }) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _settingsHeader(page, onNavigate, onClose),
          Flexible(
            child: page == _SettingsPage.home
                ? _settingsHome(style, onChanged, onNavigate)
                : _settingsBody(page, style, onChanged),
          ),
        ],
      ),
    );
  }

  Widget _settingsHeader(
    _SettingsPage page,
    ValueChanged<_SettingsPage> onNavigate,
    VoidCallback onClose,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
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
            padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
            child: Row(
              children: [
                IconButton(
                  tooltip: page == _SettingsPage.home ? 'Close' : 'Back',
                  onPressed: page == _SettingsPage.home
                      ? onClose
                      : () => onNavigate(_SettingsPage.home),
                  icon: Icon(
                    page == _SettingsPage.home ? Icons.close : Icons.arrow_back,
                    size: 20,
                    color: AppColors.text,
                  ),
                ),
                Expanded(
                  child: Text(
                    page.title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClose,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryLight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsHome(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
    ValueChanged<_SettingsPage> onNavigate,
  ) {
    final studies = style.studies;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 26),
      children: [
        _settingsEntry(
          _SettingsPage.appearance,
          Icons.palette_outlined,
          '${style.chartType.label} · ${style.name}',
          onNavigate,
        ),
        _settingsDivider(),
        _settingsEntry(
          _SettingsPage.scales,
          Icons.straighten,
          style.logScale ? 'Logarithmic' : 'Linear',
          onNavigate,
        ),
        _settingsDivider(),
        _settingsEntry(
          _SettingsPage.grid,
          Icons.grid_4x4,
          style.showGrid ? 'On' : 'Off',
          onNavigate,
        ),
        _settingsDivider(),
        _settingsEntry(
          _SettingsPage.watermark,
          Icons.branding_watermark_outlined,
          style.showWatermark ? 'On' : 'Off',
          onNavigate,
        ),
        _settingsDivider(),
        _settingsEntry(
          _SettingsPage.events,
          Icons.event_note_outlined,
          _eventsSummary(style),
          onNavigate,
        ),
        _settingsDivider(),
        _settingsEntry(
          _SettingsPage.indicators,
          Icons.show_chart,
          studies.isEmpty ? 'None' : '${studies.length} on',
          onNavigate,
        ),
        _settingsDivider(),
        _settingsEntry(
          _SettingsPage.timeZone,
          Icons.schedule,
          style.zone.describe(),
          onNavigate,
        ),
        const SizedBox(height: 22),
        _settingsDivider(),
        _settingsAction(
          'Reset settings',
          Icons.restart_alt,
          onTap: () => onChanged(ChartStyle.ink.copyWith(zoneId: style.zoneId)),
        ),
      ],
    );
  }

  String _eventsSummary(ChartStyle style) {
    final parts = <String>[
      if (style.showSessions) 'Sessions',
      if (style.showSeparators) '${style.separatorGrain.label} lines',
    ];
    return parts.isEmpty ? 'Off' : parts.join(' · ');
  }

  Widget _settingsEntry(
    _SettingsPage page,
    IconData icon,
    String value,
    ValueChanged<_SettingsPage> onNavigate,
  ) {
    return _settingsRow(
      title: page.title,
      value: value,
      leading: Icon(icon, size: 20, color: AppColors.muted),
      onTap: () => onNavigate(page),
    );
  }

  Widget _settingsBody(
    _SettingsPage page,
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
  ) {
    switch (page) {
      case _SettingsPage.appearance:
        return _appearanceSettings(style, onChanged);
      case _SettingsPage.scales:
        return _scalesSettings(style, onChanged);
      case _SettingsPage.grid:
        return _gridSettings(style, onChanged);
      case _SettingsPage.watermark:
        return _watermarkSettings(style, onChanged);
      case _SettingsPage.events:
        return _eventsSettings(style, onChanged);
      case _SettingsPage.indicators:
        return _indicatorSettings(style, onChanged);
      case _SettingsPage.timeZone:
        return _timeZoneSettings(style, onChanged);
      case _SettingsPage.home:
        return const SizedBox.shrink();
    }
  }

  Widget _appearanceSettings(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
  ) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Theme'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
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
        ),
        _settingsGroupLabel('Chart'),
        _settingsControlRow(
          'Chart type',
          _segmented(
            selected: style.chartType,
            options: [
              for (final type in ChartType.values)
                (value: type, label: type.label),
            ],
            onSelect: (type) => onChanged(style.copyWith(chartType: type)),
          ),
        ),
        _settingsDivider(),
        _settingsSwitch(
          'Volume',
          subtitle: 'Traded size under the candles',
          value: style.showVolume,
          onChanged: (value) => onChanged(style.copyWith(showVolume: value)),
        ),
        _settingsGroupLabel('Candle colours'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _colorRow('Up', style.bull, (color) {
            onChanged(style.copyWith(bull: color));
          }),
        ),
        _settingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _colorRow('Down', style.bear, (color) {
            onChanged(style.copyWith(bear: color));
          }),
        ),
      ],
    );
  }

  Widget _scalesSettings(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Price axis'),
        _settingsSwitch(
          'Logarithmic price axis',
          subtitle: 'Equal percentage moves take equal room, which is how '
              'index and crypto charts are read.',
          value: style.logScale,
          onChanged: (value) => onChanged(style.copyWith(logScale: value)),
        ),
        _settingsDivider(),
        _settingsRow(
          title: 'Scale position',
          subtitle: 'The price axis sits on the right, as on TradingView.',
          value: 'Right',
        ),
      ],
    );
  }

  Widget _gridSettings(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Grid'),
        _settingsSwitch(
          'Grid lines',
          subtitle: 'Horizontal price lines and vertical time lines.',
          value: style.showGrid,
          onChanged: (value) => onChanged(style.copyWith(showGrid: value)),
        ),
      ],
    );
  }

  Widget _watermarkSettings(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
  ) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Watermark'),
        _settingsSwitch(
          'Symbol watermark',
          subtitle: 'A faint ticker behind the candles, easy to read off a '
              'screenshot.',
          value: style.showWatermark,
          onChanged: (value) => onChanged(style.copyWith(showWatermark: value)),
        ),
      ],
    );
  }

  Widget _eventsSettings(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Sessions'),
        _settingsSwitch(
          'Session shading',
          subtitle: 'Bands for the UTC trading sessions.',
          value: style.showSessions,
          onChanged: (value) => onChanged(style.copyWith(showSessions: value)),
        ),
        if (style.showSessions)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
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
                      final next = <TradingSession>{...style.sessions};
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
        _settingsDivider(),
        _settingsSwitch(
          'Session break lines',
          subtitle: 'A rule where one session hands over to the next.',
          value: style.showSessionBreaks,
          onChanged: (value) =>
              onChanged(style.copyWith(showSessionBreaks: value)),
        ),
        _settingsGroupLabel('Periods'),
        _settingsSwitch(
          'Period separators',
          subtitle: 'A rule where a new day, week or month starts.',
          value: style.showSeparators,
          onChanged: (value) =>
              onChanged(style.copyWith(showSeparators: value)),
        ),
        if (style.showSeparators)
          _settingsControlRow(
            'Separator period',
            _segmented(
              selected: style.separatorGrain,
              options: [
                for (final grain in SeparatorGrain.values)
                  (value: grain, label: grain.label),
              ],
              onSelect: (grain) =>
                  onChanged(style.copyWith(separatorGrain: grain)),
            ),
          ),
      ],
    );
  }

  Widget _indicatorSettings(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
  ) {
    final studies = style.studies;
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Overlays'),
        for (final study in OverlayStudy.values) ...[
          _settingsSwitch(
            studyLabel(study, period: style.periodFor(study)),
            value: studies.contains(study),
            onChanged: (value) => onChanged(
              style.copyWith(
                studies:
                    value ? {...studies, study} : ({...studies}..remove(study)),
              ),
            ),
          ),
          if (studies.contains(study))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: _labelledControl(
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
          _settingsDivider(),
        ],
        _settingsGroupLabel('Lower pane'),
        _settingsControlRow(
          'Oscillator',
          _segmented(
            selected: style.oscillator,
            options: [
              for (final oscillator in Oscillator.values)
                (value: oscillator, label: oscillator.label),
            ],
            onSelect: (oscillator) =>
                onChanged(style.copyWith(oscillator: oscillator)),
          ),
        ),
        if (style.oscillator == Oscillator.rsi)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: _labelledControl(
              'RSI period',
              _stepper(
                value: style.rsiPeriod,
                min: 2,
                max: 100,
                onChanged: (value) =>
                    onChanged(style.copyWith(rsiPeriod: value)),
              ),
            ),
          ),
        if (style.oscillator == Oscillator.macd) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: _labelledControl(
              'Fast',
              _stepper(
                value: style.macdFast,
                min: 2,
                max: 60,
                onChanged: (value) =>
                    onChanged(style.copyWith(macdFast: value)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: _labelledControl(
              'Slow',
              _stepper(
                value: style.macdSlow,
                min: 3,
                max: 120,
                onChanged: (value) =>
                    onChanged(style.copyWith(macdSlow: value)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: _labelledControl(
              'Signal',
              _stepper(
                value: style.macdSignal,
                min: 2,
                max: 60,
                onChanged: (value) =>
                    onChanged(style.copyWith(macdSignal: value)),
              ),
            ),
          ),
        ],
        _settingsDivider(),
        _settingsSwitch(
          'Crosshair',
          subtitle: 'The tracking line and its price tag.',
          value: style.showCrosshair,
          onChanged: (value) => onChanged(style.copyWith(showCrosshair: value)),
        ),
      ],
    );
  }

  Widget _timeZoneSettings(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
  ) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Chart clock'),
        _settingsRow(
          title: 'Time zone',
          subtitle: style.zone.describe(),
          value: 'Change',
          trailing: Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () async {
            final zone = await _pickZone(style.zone);
            if (zone == null) return;
            onChanged(style.copyWith(zoneId: zone.id));
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            'The price axis and the day, week and month separators follow this '
            'clock. Session shading stays on UTC market hours, so London opens '
            'at 07:00 UTC wherever you trade from.',
            style: TextStyle(
              color: AppColors.faint,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsGroupLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
      );

  Widget _settingsDivider() => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 20),
        color: AppColors.border.withAlpha(120),
      );

  Widget _settingsRow({
    required String title,
    String? subtitle,
    String? value,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }

  Widget _settingsSwitch(
    String title, {
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _settingsRow(
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: SizedBox(
        width: 48,
        height: 28,
        child: FittedBox(
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: AppColors.muted,
            inactiveTrackColor: AppColors.surfaceAlt,
            trackOutlineColor: WidgetStateProperty.all(AppColors.borderStrong),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Widget _settingsControlRow(String title, Widget control) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          control,
        ],
      ),
    );
  }

  Widget _settingsAction(
    String title,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppColors.danger),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subLabel(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );

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
            // The card behind this is the chart's own background, which is
            // white on the day theme. The app palette writes white here and the
            // button vanished, so both take the canvas colours.
            style: TextStyle(
              color: _style.muted,
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
              foregroundColor: _style.text,
              side: BorderSide(color: _style.axis),
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
                text: _staleAt == null ? 'LIVE' : 'OFFLINE',
                tone: _staleAt == null ? Tone.positive : Tone.negative,
              ),
              const SizedBox(width: 8),
              // Expanded instead of Spacer: the timestamp is the part that has
              // to give way when the pills and a doubled text size leave no
              // room, and a Spacer only reports the overflow.
              Expanded(
                // While the crosshair is out, the legend reads that candle
                // instead of the clock: O H L C is what a trader measures a
                // level against, and it is where a desk puts it.
                child: _hover == null
                    ? (_updated == null
                        ? const SizedBox.shrink()
                        : Text(
                            'Updated '
                            '${DateFormat('HH:mm:ss').format(_updated!)}',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tabular.copyWith(
                              color: AppColors.faint,
                              fontSize: 9.5,
                            ),
                          ))
                    : Text(
                        'O ${_hover!.open.toStringAsFixed(widget.instrument.decimals)}'
                        '  H ${_hover!.high.toStringAsFixed(widget.instrument.decimals)}'
                        '  L ${_hover!.low.toStringAsFixed(widget.instrument.decimals)}'
                        '  C ${_hover!.close.toStringAsFixed(widget.instrument.decimals)}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tabular.copyWith(
                          color: _hover!.isUp
                              ? AppColors.success
                              : AppColors.danger,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
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
    if (from == null || to == null) {
      return _staleAt == null
          ? 'Live · newest candles'
          : 'Offline · last known candles';
    }
    return '${_stamp(from)} → ${_stamp(to)}';
  }

  Future<void> _openTimeFrameSheet() async {
    final choice = await showChartTimeFrameSheet(
      context: context,
      interval: _interval,
      refused: _refusedIntervals,
    );
    if (choice == null || !mounted) return;
    // The picker only returns the live tail, but the type still carries a
    // window: a caller that builds one keeps working instead of silently
    // ignoring its dates.
    if (!choice.isLive && choice.from != null && choice.to != null) {
      await _applyWindow(
        choice.from!,
        choice.to!,
        choice.interval ?? _interval,
      );
      return;
    }
    final picked = choice.interval;
    if (picked == null) return;
    await _setInterval(picked);
  }

  /// Switches candle size on the live tail.
  ///
  /// The picker no longer sets a date range: a chart is a candle size and a
  /// stream of bars, and the range is what the trader pans into. The window
  /// never changes here, so the refresh timer keeps rolling and the newest bar
  /// keeps arriving.
  Future<void> _setInterval(ChartInterval next) async {
    if (next == _interval && !_customWindow) return;
    _stopPlay();
    final cached = _market.cached(widget.instrument, next);
    setState(() {
      _interval = next;
      _windowFrom = null;
      _windowTo = null;
      _replay = null;
      _error = null;
      // A different size is a different series: the stamp of the old one says
      // nothing about these candles.
      _staleAt = null;
      _candles = cached ?? const [];
      _loading = cached == null || cached.isEmpty;
    });
    await _load();
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
                        _staleAt == null
                            ? '${_interval.detail} · tap to change'
                            : '${_interval.detail} · offline copy from '
                                '${DateFormat('EEE HH:mm').format(_staleAt!)}',
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
              'Drag to scroll · pinch to zoom · drag a level line to move it'
              ' · tap an object for edit, clone or delete · '
              '${_style.zone.describe()}',
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
                'Drag a line on the chart to place a level — for entry the time moves too. Everything reaches the form only once you confirm.',
            trailing: _entry == null && _stop == null && _take == null
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
    // The exit is deliberately left out: the trade form finds it from the
    // candles after entry, so a hand-pinned exit cannot turn a loss into a win.
    final selection = ChartSelection(
      entry: _entry,
      stop: _stop,
      take: _take,
      entryTime: _entryTime,
      direction: _selectionDirection ?? widget.direction,
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
    required this.onLevelMoved,
    required this.drawings,
    required this.selectedDrawing,
    required this.positionOutcomes,
    required this.onDrawingSelected,
    required this.onDrawingTapped,
    required this.onDrawingMoved,
    required this.onDrawingMoveEnd,
    this.height,
    this.onReachStart,
    this.pendingKind,
    this.pendingSide,
    required this.onDrawingCreated,
    this.magnet = true,
    this.onCrosshair,
    this.onPlacing,
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
  final void Function(Marker marker, double price, DateTime? time) onLevelMoved;
  final List<ChartDrawing> drawings;
  final int? selectedDrawing;
  final List<ResolvedExit?> positionOutcomes;
  final ValueChanged<int?> onDrawingSelected;

  /// A tap landed on an object: the screen offers edit, clone and delete.
  final ValueChanged<int> onDrawingTapped;
  final void Function(int index, ChartDrawing drawing) onDrawingMoved;
  final VoidCallback onDrawingMoveEnd;

  /// The tool waiting for a place on the chart, armed from the tools sheet.
  /// While one is set the canvas stops panning and starts placing: press and
  /// drag sizes the object, a plain tap drops it at a usable default size.
  final DrawingKind? pendingKind;
  final PositionSide? pendingSide;

  /// A placed object, finished and ready for the screen to keep.
  final ValueChanged<ChartDrawing> onDrawingCreated;

  /// Snap a placed or dragged point onto a wick, open, high, low or close.
  final bool magnet;

  /// The candle under the crosshair, or null when the crosshair is away. The
  /// screen uses it for the O H L C legend in the header.
  final ValueChanged<Candle?>? onCrosshair;

  /// True once the finger has put down the first point of the object being
  /// placed, so the banner can count.
  final ValueChanged<bool>? onPlacing;

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

  /// Which anchor of the object under the finger is being dragged. Null means
  /// the finger is on the body, so the object moves as one piece.
  int? _dragHandle;

  /// Placement in progress: where the finger went down, and the object it has
  /// built so far. Both are cleared the moment it is committed or abandoned.
  Offset? _placeFrom;
  ChartDrawing? _preview;

  /// Where the last touch was, so a release can finish what the drag was doing
  /// without needing a focal point from the end event.
  Offset _lastTouch = Offset.zero;
  List<ChartPoint> _brush = const [];
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
    if (oldWidget.pendingKind != null && widget.pendingKind == null) {
      _cancelPlace();
    }
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

  /// The price under a finger, pulled onto the nearest open, high, low or close
  /// of the candle beneath it when it lands within a few pixels.
  ///
  /// This is the magnet every desk has. Without it a level placed "on the wick"
  /// is a level placed near the wick, and nothing on screen says so; with it a
  /// press that looks like the high is the high, while a press out in open space
  /// still lands exactly where it was released.
  double _priceAt(Offset local) {
    final raw = _priceFor(local);
    if (!widget.magnet) return raw;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    final candles = widget.candles;
    if (plotW <= 0 || candles.isEmpty) return raw;
    final ratio = (local.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, candles.length);
    var bestDy = 7.0;
    double? best;
    for (
      var i = math.max(0, index - 1);
      i <= math.min(candles.length - 1, index + 1);
      i++
    ) {
      final candle = candles[i];
      for (final price in [candle.open, candle.high, candle.low, candle.close]) {
        final dy = (_yFor(price) - local.dy).abs();
        if (dy < bestDy) {
          bestDy = dy;
          best = price;
        }
      }
    }
    return best ?? raw;
  }

  /// A finger position as a chart point. Time is the candle's own stamp, so an
  /// object dropped today still sits on the same bar when the window moves.
  ChartPoint _pointAt(Offset local) {
    final time = _timeFor(local);
    return ChartPoint(
      ms: time == null
          ? DateTime.now().toUtc().millisecondsSinceEpoch
          : time.toUtc().millisecondsSinceEpoch,
      price: _priceAt(local),
    );
  }

  /// The second point a tap uses when the trader did not drag: far enough right
  /// to read as a box or a line, with the trend tools sloping so they are not a
  /// zero-height smear.
  Offset _defaultEnd(DrawingKind kind, Offset from) {
    final plotW = _size.width - TradingChartPainter.axisWidth;
    final dx = math.min(plotW * 0.3, 120.0);
    final dy = switch (kind) {
      DrawingKind.trend || DrawingKind.measure => -24.0,
      DrawingKind.fibExtension => 40.0,
      _ => 70.0,
    };
    return Offset(from.dx + dx, from.dy + dy);
  }

  double _defaultRisk(double price) => price == 0 ? 1 : (price.abs() * 0.0025);

  /// Builds the object a tool would produce between two finger positions.
  ChartDrawing _draftFor(
    DrawingKind kind,
    Offset from,
    Offset to, {
    required bool sized,
  }) {
    final start = _pointAt(from);
    final endPoint = _pointAt(sized ? to : _defaultEnd(kind, from));
    final side = widget.pendingSide;
    switch (kind) {
      case DrawingKind.ray:
        return ChartDrawing.ray(price: start.price);
      case DrawingKind.position:
        final long = (side ?? PositionSide.long) == PositionSide.long;
        final risk = _defaultRisk(start.price);
        return ChartDrawing.position(
          side: side ?? PositionSide.long,
          startMs: start.ms,
          endMs: endPoint.ms,
          entry: start.price,
          stop: long ? start.price - risk : start.price + risk,
          target: long ? start.price + risk * 2 : start.price - risk * 2,
        );
      case DrawingKind.trend:
        return ChartDrawing.trend(
          startMs: start.ms,
          startPrice: start.price,
          endMs: endPoint.ms,
          endPrice: endPoint.price,
        );
      case DrawingKind.vline ||
          DrawingKind.text ||
          DrawingKind.arrowUp ||
          DrawingKind.arrowDown:
        return ChartDrawing.points(kind: kind, points: [start]);
      case DrawingKind.brush:
        return ChartDrawing.points(
          kind: kind,
          points: _brush.length < 2 ? [start, endPoint] : _brush,
        );
      default:
        return ChartDrawing.points(kind: kind, points: [start, endPoint]);
    }
  }

  void _beginPlace(Offset local) {
    final kind = widget.pendingKind;
    if (kind == null) return;
    _settle.stop();
    widget.onPlacing?.call(true);
    setState(() {
      _placeFrom = local;
      _brush = [_pointAt(local)];
      _crosshair = local;
      _preview = _draftFor(kind, local, local, sized: false);
    });
  }

  void _updatePlace(Offset local) {
    final kind = widget.pendingKind;
    final from = _placeFrom;
    if (kind == null || from == null) return;
    final moved = (local - from).distance > 6;
    setState(() {
      if (kind == DrawingKind.brush && moved) {
        _brush = [..._brush, _pointAt(local)];
      }
      _crosshair = local;
      _preview = _draftFor(kind, from, local, sized: moved);
    });
  }

  void _commitPlace() {
    final placed = _preview;
    setState(() {
      _preview = null;
      _placeFrom = null;
      _brush = const [];
      _crosshair = null;
    });
    widget.onPlacing?.call(false);
    widget.onCrosshair?.call(null);
    if (placed != null) widget.onDrawingCreated(placed);
  }

  /// Abandons a placement in progress. Called when the tool is disarmed from
  /// outside the canvas, so a half-built object cannot be left on screen.
  void _cancelPlace() {
    if (_preview == null && _placeFrom == null) return;
    setState(() {
      _preview = null;
      _placeFrom = null;
      _brush = const [];
    });
    widget.onPlacing?.call(false);
  }

  /// Whether a press has landed on the object that is already selected.
  bool _hitsSelected(Offset local) {
    final selected = widget.selectedDrawing;
    if (selected == null || selected >= widget.drawings.length) return false;
    final drawing = widget.drawings[selected];
    // A locked object is held exactly where it is. Tapping it still opens its
    // menu, which is the only way back to unlocking it.
    if (drawing.look.locked || drawing.look.hidden) return false;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (plotW <= 0) return false;
    final distance = _drawingDistance(drawing, local, plotW);
    return distance != null && distance <= 14;
  }

  /// The draggable dots of an object: its anchors, or a trend line's two ends.
  List<Offset> _anchorsOf(ChartDrawing drawing, double plotW) {
    if (drawing.kind == DrawingKind.trend) {
      final start = _indexForTime(drawing.startMs);
      final end = _indexForTime(drawing.endMs);
      if (start == null || end == null) return const [];
      return [
        Offset(_xForIndex(start, plotW), _yFor(drawing.startPrice)),
        Offset(_xForIndex(end, plotW), _yFor(drawing.endPrice)),
      ];
    }
    if (!drawing.isAnchored) return const [];
    return [
      for (final point in drawing.points)
        if (_indexForTime(point.ms) case final index?)
          Offset(_xForIndex(index, plotW), _yFor(point.price)),
    ];
  }

  /// Which anchor a press has taken hold of, or null when it is on the body.
  int? _handleAt(ChartDrawing drawing, Offset local, double plotW) {
    final anchors = _anchorsOf(drawing, plotW);
    int? best;
    var bestDistance = 18.0;
    for (var i = 0; i < anchors.length; i++) {
      final distance = (anchors[i] - local).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
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
    // An armed tool owns the next tap: it lands where the trader put their
    // finger, at a size they can already see. Nothing is created invisibly in
    // the middle of the window.
    if (widget.pendingKind != null) {
      if (_preview == null) _beginPlace(local);
      _commitPlace();
      return;
    }
    final panes = TradingChartPainter.paneLayout(_size.height, widget.style);
    final inPricePane =
        local.dy >= panes.priceTop && local.dy <= panes.priceTop + panes.priceH;

    // A tap can only ever select something. Tools place their own object when
    // they are picked, so a stray tap never starts a point.
    if (inPricePane) {
      final hit = _nearestDrawing(local);
      if (hit != null) {
        widget.onDrawingSelected(hit);
        widget.onDrawingTapped(hit);
        return;
      }
    }
    // Nothing else happens on a tap: levels are set by dragging their handles
    // or by editing the fields below the chart, never by an accidental touch.
    if (widget.selectedDrawing != null) widget.onDrawingSelected(null);
  }

  void _onScaleStart(ScaleStartDetails details) {
    // A new touch owns the chart: stop the coast where it is.
    _settle.stop();
    _lastTouch = details.localFocalPoint;
    if (widget.pendingKind != null) {
      _beginPlace(details.localFocalPoint);
      return;
    }
    // A selected object is grabbed directly: press on it and drag, instead of
    // the long press every other object needs. Once it is selected, the trader
    // has already said which thing they mean.
    if (_hitsSelected(details.localFocalPoint)) {
      _startDrag(details.localFocalPoint);
      return;
    }
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
    // Whatever was being placed is finished on lift-off: the finger has said
    // how big it should be, and leaving it hanging would be a tool that never
    // commits.
    if (_placeFrom != null) {
      _commitPlace();
      return;
    }
    if (_drawingIndex != null) {
      _endDrag(_lastTouch);
      _reportCrosshair(null);
      return;
    }
    setState(() => _crosshair = null);
    _reportCrosshair(null);
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
    if (_placeFrom != null) {
      _updatePlace(details.localFocalPoint);
      return;
    }
    if (_drawingIndex != null) {
      _lastTouch = details.localFocalPoint;
      _updateDrag(details.localFocalPoint);
      return;
    }
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
    _reportCrosshair(details.localFocalPoint);
  }

  /// Tells the screen which candle the crosshair is over. The chart itself has
  /// no legend to write into, and the header does.
  void _reportCrosshair(Offset? local) {
    final report = widget.onCrosshair;
    if (report == null) return;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (local == null || widget.candles.isEmpty || plotW <= 0) {
      report(null);
      return;
    }
    final ratio = (local.dx / plotW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, widget.candles.length);
    report(widget.candles[index.clamp(0, widget.candles.length - 1)]);
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
    if (drawing.points.isNotEmpty && drawing.kind != DrawingKind.trend) {
      if (widget.candles.isEmpty) return double.infinity;
      // Distance to the object's bounding box: zero inside it, which is what
      // makes a box or a fib ladder selectable by tapping anywhere on it.
      final xs = <double>[];
      final ys = <double>[];
      for (final point in drawing.points) {
        final index = _indexForTime(point.ms);
        xs.add(
          index == null
              ? (point.ms < widget.candles.first.time.millisecondsSinceEpoch
                  ? 0.0
                  : plotW)
              : _xForIndex(index, plotW),
        );
        ys.add(_yFor(point.price));
      }
      final left = xs.reduce(math.min);
      final right = xs.reduce(math.max);
      final top = ys.reduce(math.min);
      final bottom = ys.reduce(math.max);
      final dx = local.dx < left
          ? left - local.dx
          : (local.dx > right ? local.dx - right : 0.0);
      final dy = local.dy < top
          ? top - local.dy
          : (local.dy > bottom ? local.dy - bottom : 0.0);
      return math.sqrt(dx * dx + dy * dy);
    }
    if (drawing.isPosition) {
      final start = _indexForTime(drawing.startMs);
      // An anchor older than the loaded window draws from the left edge, so a
      // tap anywhere on the box still finds it.
      if (start == null &&
          drawing.startMs > widget.candles.last.time.millisecondsSinceEpoch) {
        return null;
      }
      final left = start == null ? 0.0 : _xForIndex(start, plotW);
      if (local.dx < left - 12) return null;
      // The box stops at its end time, so a tap beyond its right edge belongs
      // to the chart and not to the drawing.
      final endIndex = drawing.endMs > 0
          ? _indexForTime(drawing.endMs)
          : widget.candles.length - 1.0;
      if (endIndex != null && local.dx > _xForIndex(endIndex, plotW) + 12) {
        return null;
      }
      var best = double.infinity;
      for (final level in PositionLevel.values) {
        final price = drawing.levelFor(level);
        if (price == null) continue;
        best = math.min(best, (_yFor(price) - local.dy).abs());
      }
      if (!best.isFinite) return null;
      // Inside the box the whole tool is the target, not just its three lines.
      // Distance is measured to the nearest level, so anything nearer than the
      // box's own half-height is a hit on the body — which is what makes the
      // position draggable from anywhere on it, the way the desktop tool is.
      final top = math.max(
        _yFor(drawing.target ?? drawing.levelFor(PositionLevel.target) ?? 0),
        _yFor(drawing.stop ?? drawing.levelFor(PositionLevel.stop) ?? 0),
      );
      final bottom = math.min(
        _yFor(drawing.target ?? drawing.levelFor(PositionLevel.target) ?? 0),
        _yFor(drawing.stop ?? drawing.levelFor(PositionLevel.stop) ?? 0),
      );
      if (local.dy >= top && local.dy <= bottom) return 0;
      return best;
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
      // Hidden objects are not on the chart, so the finger cannot find them.
      if (widget.drawings[i].look.hidden) continue;
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
    // A drag on a dot moves that dot. Anything else slides the whole object.
    final handle = _dragHandle;
    if (handle != null) {  
      return original.withPoint(handle, _pointAt(local));
    }
    // Down the screen is down the price axis. This used to be written the other
    // way round, which is why an object travelled upwards under a finger
    // travelling downwards.
    final priceDelta = _priceFor(local) - _priceFor(_dragOrigin);
    if (original.kind == DrawingKind.ray) {
      return ChartDrawing.ray(
        id: original.id,
        price: (original.price ?? 0) + priceDelta,
      );
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

    // An anchor-based object moves as one piece: every point takes the same
    // price and time shift, so dragging a fib ladder does not stretch it.
    if (original.points.isNotEmpty && original.kind != DrawingKind.trend) {
      return original.translated(
        shiftTime: shiftTime,
        priceDelta: priceDelta,
      );
    }

    if (original.isPosition) {
      // The right grip changes how far the calibration runs and leaves the
      // levels alone.
      if (_dragEdge) {
        final endMs = original.endMs > 0
            ? original.endMs
            : candles.last.time.millisecondsSinceEpoch;
        return original.withEnd(shiftTime(endMs));
      }
      // Grabbing one of the three lines moves only that level; grabbing the box
      // itself moves all of them together, which is how the levels are set.
      final level = _dragLevel;
      if (level != null) {
        return original.copyWithLevel(level, _priceFor(local));
      }
      return original.shifted(
        priceDelta: priceDelta,
        startMs: shiftTime(original.startMs),
        // The whole box travels, right edge included.
        endMs: shiftTime(
          original.endMs > 0
              ? original.endMs
              : candles.last.time.millisecondsSinceEpoch,
        ),
      );
    }

    return ChartDrawing.trend(
      id: original.id,
      startMs: shiftTime(original.startMs),
      startPrice: original.startPrice + priceDelta,
      endMs: shiftTime(original.endMs),
      endPrice: original.endPrice + priceDelta,
    );
  }

  /// The position level under the finger, or null when the drag should move the
  /// whole box instead of one line.
  PositionLevel? _nearestPositionLevel(ChartDrawing drawing, Offset local) {
    PositionLevel? best;
    // Deliberate, not incidental: a level line is grabbed only when the finger
    // lands on it, so a drag from the middle of the box moves the whole tool.
    var distance = 14.0;
    for (final level in PositionLevel.values) {
      final price = drawing.levelFor(level);
      if (price == null) continue;
      final dy = (_yFor(price) - local.dy).abs();
      if (dy < distance) {
        distance = dy;
        best = level;
      }
    }
    return best;
  }

  void _startDrag(Offset local) {
    if (widget.pendingKind != null) return;
    final drawing = _nearestDrawing(local);
    if (drawing != null) {
      final original = widget.drawings[drawing];
      if (original.look.locked) {
        widget.onDrawingSelected(drawing);
        return;
      }
      final plotW = _size.width - TradingChartPainter.axisWidth;
      setState(() {
        _crosshair = null;
        _drawingIndex = drawing;
        _drawingOriginal = original;
        _dragOrigin = local;
        _dragHandle = plotW > 0 ? _handleAt(original, local, plotW) : null;
        _dragEdge = plotW > 0 &&
            _dragHandle == null &&
            _nearRightEdge(original, local, plotW);
        _dragLevel = original.isPosition && !_dragEdge
            ? _nearestPositionLevel(original, local)
            : null;
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

  PositionLevel? _dragLevel;

  /// True while the finger holds the position box's right grip.
  bool _dragEdge = false;

  bool _nearRightEdge(ChartDrawing drawing, Offset local, double plotW) {
    if (!drawing.isPosition) return false;
    final endIndex = drawing.endMs > 0
        ? _indexForTime(drawing.endMs)
        : (widget.candles.isEmpty ? null : widget.candles.length - 1.0);
    if (endIndex == null) return false;
    return (local.dx - _xForIndex(endIndex, plotW)).abs() <= 16;
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
        _dragLevel = null;
        _dragEdge = false;
        _dragHandle = null;
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
                      selectedDrawing: widget.selectedDrawing,
                      positionOutcomes: widget.positionOutcomes,
                      preview: _preview,
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
                price == null ? 'Not set' : chartPrice(price!, instrument),
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
    style: style,
    symbol: symbol,
    selectedDrawing: null,
    positionOutcomes: const [],
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

/// Searchable clock picker for the chart.
///
/// Starts on the zones a trader is most likely to want, then offers every IANA
/// zone the bundled database knows. Selecting one returns it; the style sheet
/// stores the id and the axis follows immediately.
class _ZoneSheet extends StatefulWidget {
  const _ZoneSheet({required this.current});

  final ChartZone current;

  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zones = ChartZone.search(_query);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chart time zone',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: false,
                style: TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search a city or zone',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: zones.length,
                itemBuilder: (context, index) {
                  final zone = zones[index];
                  final selected = zone.id == widget.current.id;
                  return ListTile(
                    dense: true,
                    title: Text(
                      zone.label,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      zone.isDevice
                          ? zone.describe()
                          : '${zone.id} · ${zone.describe()}',
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 10,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check, size: 18, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(zone),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page in the chart settings sheet. TradingView groups chart settings the
/// same way: a short list of names, each opening its own page.
enum _SettingsPage {
  home('Chart settings'),
  appearance('Appearance'),
  scales('Scales'),
  grid('Grid'),
  watermark('Watermark'),
  events('Events'),
  indicators('Indicators'),
  timeZone('Time zone');

  const _SettingsPage(this.title);

  final String title;
}
