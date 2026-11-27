import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/chart_replay.dart';
import 'time_frame_sheet.dart';
import '../core/chart_drawings.dart';
import '../core/chart_layouts.dart';
import '../core/chart_magnet.dart';
import '../core/chart_presets.dart';
import '../core/chart_projection.dart';
import '../core/chart_scale.dart';
import '../core/chart_sessions.dart';
import '../core/chart_theme.dart';
import '../core/chart_view.dart';
import '../l10n/gen/app_localizations.dart';
import '../core/chart_zone.dart';
import '../core/indicators.dart';
import '../core/level_touch.dart';
import '../core/subscription.dart';
import '../core/trade_exit.dart' show ResolvedExit;
import '../core/instruments.dart';
import '../services/journal_api.dart';
import '../services/alerts.dart';
import '../services/chart_drawings_sync.dart';
import '../services/chart_templates_sync.dart';
import '../services/market_data.dart';
import '../ui/chart/chart_marker.dart';
import '../ui/chart/chart_painter.dart';
import 'alerts_screen.dart';
import '../ui/chart/drawings_sheet.dart';
import '../ui/chart/layouts_sheet.dart';
import '../ui/chart/object_settings.dart';
import '../ui/chart/sync_badge.dart';
import '../ui/color_wheel.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'package:mtl_trader_mobile/core/friendly_error.dart';

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

class _ChartPickerScreenState extends State<ChartPickerScreen>
    with WidgetsBindingObserver {
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
  /// The magnet lives in the saved chart style: a trader who picks Strong has
  /// picked it for this instrument, and reopening the chart must not undo it.
  MagnetMode get _magnet => _style.magnet;

  /// Off → weak → strong → off, saved immediately so the next open matches the
  /// icon the trader is looking at.
  void _cycleMagnet() => _setMagnet(_style.magnet.next);

  /// Sets the magnet mode and stores it with the rest of the chart style, so
  /// the sheet's toggle and the rail button agree after a restart.
  void _setMagnet(MagnetMode mode) {
    setState(() => _style = _style.copyWith(magnet: mode));
    unawaited(ChartStyle.saveLayout(widget.instrument.symbol, _style));
  }

  /// The magnet's own icon, so the rail button always says which mode is live
  /// rather than only whether it is on.
  IconData get _magnetIcon => switch (_magnet) {
        MagnetMode.off => Icons.hdr_off,
        MagnetMode.weak => Icons.hdr_weak,
        MagnetMode.strong => Icons.hdr_strong,
      };

  /// Candle under the crosshair, so the header can show its O H L C the way a
  /// desktop chart does while the pointer travels.

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

  /// Keep the armed tool armed after it places an object.
  ///
  /// Six levels should cost one trip to the tools sheet, not six. Off by
  /// default, because a stray second tap after finishing a shape would
  /// otherwise leave a duplicate on the chart.
  bool _keepDrawing = false;

  /// Crosshair mode. When it is on, a one-finger drag scrubs the crosshair
  /// instead of panning; when it is off, a drag always pans and a stationary
  /// long press is the only other way to bring the crosshair out.
  bool _crosshairMode = false;
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

  /// Decimals every price on this chart prints with. The style's precision
  /// wins over the instrument's own, because "1/100 on a 5-decimal pair" is a
  /// trader deciding how much noise to read, not a correction.
  int get _decimals => _style.precision ?? widget.instrument.decimals;

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
    WidgetsBinding.instance.addObserver(this);
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
    _restoreLayouts();
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
    WidgetsBinding.instance.removeObserver(this);
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
    // `force` skips the client-side candle cache. Without it the cache lives
    // for half a bar while the timer fires every third of a bar, so every other
    // poll returned the series that was already on screen and a one-minute
    // chart only moved once a minute.
    _refreshTimer = Timer.periodic(_refreshPeriod, (_) => _loadTail());
  }

  /// Fetches only the moving bars and merges them into what is on screen.
  ///
  /// The full series is loaded once; after that the newest candle is kept in
  /// step with the feed about once a second, which is as close to MT5's moving
  /// bar as a polling client gets. A past window is never polled.
  Future<void> _loadTail() async {
    if (_windowFrom != null) return;
    try {
      final tail = await _market.candles(
        widget.instrument,
        _interval,
        force: true,
        tail: true,
      );
      if (!mounted || tail.isEmpty) return;
      final byTime = {
        for (final candle in _candles)
          candle.time.millisecondsSinceEpoch: candle,
      };
      for (final candle in tail) {
        byTime[candle.time.millisecondsSinceEpoch] = candle;
      }
      final merged = byTime.values.toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      final previousClose = _candles.isEmpty ? null : _candles.last.close;
      setState(() {
        _candles = merged;
        _staleAt = null;
        _updated = DateTime.now();
      });
      _checkLevelTouches(previousClose, merged);
    } catch (_) {
      // A missed tail keeps the last good chart; the next tick retries.
    }
  }

  /// A phone that was asleep has a timer that did not fire; refresh the live
  /// tail as soon as the trader is looking again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_windowFrom != null) return;
    unawaited(_load(silent: true, force: true));
  }

  /// How often the moving bars are refetched.
  ///
  /// Every second up to five minutes, which is what makes the newest candle
  /// move like a terminal instead of jumping once a bar. Longer sizes gain
  /// nothing from that cadence, so they slow down rather than spend requests.
  Duration get _refreshPeriod {
    final bar = _interval.size.inMilliseconds;
    if (bar >= 14400000) return const Duration(seconds: 5);
    if (bar >= 900000) return const Duration(seconds: 2);
    return const Duration(seconds: 1);
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
        _error = friendlyError(error);
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
    // Alert lines are told apart from plain levels, because reaching one
    // changes the object itself rather than only sending a notification.
    final alertLines = <double, int>{};
    for (var i = 0; i < _drawings.length; i++) {
      final drawing = _drawings[i];
      if (drawing.kind != DrawingKind.ray) continue;
      if (drawing.look.alert) {
        add('alert', drawing.price);
        final price = drawing.price;
        if (price != null) alertLines[price] = i;
      } else {
        add('level', drawing.price);
      }
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
      if (hit.label == 'alert') {
        final index = alertLines[hit.price];
        if (index != null) _markAlertFired(index);
      }
      unawaited(
        Alerts.instance.levelTouched(
          symbol: widget.instrument.symbol,
          label: hit.label,
          price: hit.price,
          crossedFrom: previousClose,
          crossedTo: close,
          decimals: _decimals,
        ),
      );
    }
  }

  /// Records that an alert line's price was reached.
  ///
  /// The flag lives on the object, so it synchronises with the line and
  /// survives a restart; a side table would forget on the next launch and the
  /// alert would fire again for a level the trader already saw.
  void _markAlertFired(int index) {
    if (index < 0 || index >= _drawings.length) return;
    final drawing = _drawings[index];
    if (drawing.look.fired) return;
    final next = [..._drawings];
    next[index] = drawing.withLook(drawing.look.copyWith(fired: true));
    _commitDrawings(next);
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
              chartPrice(last, instrument, decimals: _decimals),
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
          IconButton(
            tooltip:
                _crosshairMode ? 'Crosshair mode on' : 'Crosshair mode off',
            onPressed: () => setState(() => _crosshairMode = !_crosshairMode),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.center_focus_strong,
              size: 18,
              color: _crosshairMode ? _style.text : _style.muted,
            ),
          ),
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
            icon: _magnetIcon,
            tooltip: 'Magnet: ${_magnet.label}',
            onTap: _cycleMagnet,
            active: _magnet != MagnetMode.off,
          ),
          button(
            icon: Icons.tune,
            tooltip: 'Chart style',
            onTap: _openStyleSheet,
          ),
          button(
            icon: Icons.more_horiz,
            tooltip: 'Analysis hub',
            onTap: _openAnalysisHub,
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
            tooltip: 'Magnet: ${_magnet.label}',
            onPressed: _cycleMagnet,
            icon: Icon(
              _magnetIcon,
              size: 20,
              color: _magnet == MagnetMode.off
                  ? AppColors.muted
                  : AppColors.primaryLight,
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
      if (last != null) chartPrice(last, instrument, decimals: _decimals),
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
            tooltip: 'Magnet: ${_magnet.label}',
            onPressed: _cycleMagnet,
            icon: Icon(
              _magnetIcon,
              size: 19,
              color: _magnet == MagnetMode.off ? _style.muted : _style.text,
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
                Icon(open ? Icons.close : Icons.swap_vert,
                    size: 15, color: ink),
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
      decimals: _decimals,
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
      keepDrawing: _keepDrawing,
      crosshairMode: _crosshairMode,
      onFinishPlacement: _disarmTool,
      magnet: _magnet,
      onPlacing: (down) {
        if (down == _placing) return;
        setState(() => _placing = down);
      },
      onDrawingCreated: (drawing) => unawaited(_placeDrawing(drawing)),
      onQuickAction: _openQuickActions,
    );

    final armed = _armingKind != null || _armingSide != null;
    final selected = _selectedDrawing;
    // A locked object still shows its bar: More is the only door back to
    // Unlock, and hiding the bar would leave it locked forever.
    final showBar = selected != null && selected < _drawings.length && !armed;
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
    // The wording the spec asks for: tell the trader which point they are on,
    // then what the finger has to do next — not "drag", which hides the tap
    // that also works.
    final title = _placing
        ? (total > 1 ? 'Move to size it, then lift to finish' : 'Lift to place')
        : (total > 1 ? 'Tap to set the first point' : 'Tap to place');
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
          // Which magnet the anchors will obey, said out loud while it still
          // matters. A trader placing a level should not have to remember what
          // the corner button was set to.
          if (_magnet != MagnetMode.off) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_magnetIcon, size: 13, color: AppColors.muted),
                const SizedBox(width: 3),
                Text(
                  '${_magnet.label} magnet',
                  style: tabular.copyWith(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
          IconButton(
            tooltip: _keepDrawing ? 'Keep drawing on' : 'Keep drawing off',
            onPressed: () => setState(() => _keepDrawing = !_keepDrawing),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _keepDrawing ? Icons.lock_outline : Icons.lock_open,
              size: 17,
              color: _keepDrawing
                  ? drawingColor
                  : const Color(0xFFF2F4F7).withAlpha(150),
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
          // The name is the door to the object's settings, the way tapping a
          // title opens settings in every charting app: one obvious place for
          // style, coordinates and the label.
          Expanded(
            child: InkWell(
              onTap: () => _editDrawing(index),
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: Row(
                children: [
                  Flexible(
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
                  const SizedBox(width: 2),
                  Icon(Icons.tune, size: 13, color: AppColors.muted),
                ],
              ),
            ),
          ),
          action(
            icon: Icons.more_vert,
            tooltip: 'More actions',
            onTap: () => unawaited(_openDrawingActions(index)),
          ),
          // Extend right lives in the object's Edit sheet, so the top bar keeps
          // enough width for the controls a trader reaches for mid-drag.
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

  /// What a trader does with a price they have just pointed at.
  ///
  /// A crosshair is only useful if it leads somewhere: the four things here are
  /// the ones that leave a mark on this chart — a level they can see later, an
  /// entry they can trade from, and the number itself. Anything that needs a
  /// broker order stays out until the app can actually place one.
  Future<void> _openQuickActions(double price, DateTime time) async {
    final decimals = _decimals;
    final label = price.toStringAsFixed(decimals);
    final clock = DateFormat('d MMM HH:mm').format(time);
    final symbol = widget.instrument.symbol;
    // An alert above the market is waiting for price to rise into it, so it
    // takes the up colour; one below is waiting for a fall.
    final last = _lastVisible?.close;
    final alertColour = last != null && price < last
        ? (_style.alertDown ?? _style.bear)
        : (_style.alertUp ?? _style.bull);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        Widget row({
          required IconData icon,
          required String title,
          required String subtitle,
          required String value,
          Color? tone,
        }) {
          return ListTile(
            dense: true,
            leading: Icon(icon, size: 20, color: tone ?? AppColors.muted),
            title: Text(
              title,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
            trailing:
                Icon(Icons.chevron_right, size: 16, color: AppColors.faint),
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$symbol · $clock',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              row(
                icon: Icons.notifications_active_outlined,
                title: 'Add alert on $symbol at $label',
                subtitle: 'A line that fires when price reaches this level',
                value: 'alert',
                tone: alertColour,
              ),
              row(
                icon: Icons.horizontal_rule,
                title: 'Pin a level here',
                subtitle: 'A plain line, no notification',
                value: 'level',
                tone: drawingColor,
              ),
              row(
                icon: Icons.login,
                title: 'Use as entry',
                subtitle: 'Fills the entry price and this candle’s time',
                value: 'entry',
                tone: AppColors.primary,
              ),
              row(
                icon: Icons.copy_all_outlined,
                title: 'Copy price',
                subtitle: label,
                value: 'copy',
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'alert':
        _addDrawing(
          ChartDrawing.ray(
            price: price,
            look: DrawingLook(alert: true, tint: alertColour),
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alert set at $label.'),
            duration: const Duration(seconds: 2),
          ),
        );
        break;
      case 'level':
        _addDrawing(ChartDrawing.ray(price: price));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Level pinned at $label.'),
            duration: const Duration(seconds: 2),
          ),
        );
        break;
      case 'entry':
        // The canvas takes the markers from these fields, so setting them is
        // enough: it re-reads its levels on the next build.
        setState(() {
          _entry = price;
          _entryTime = time;
        });
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: label));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label copied.'),
            duration: const Duration(seconds: 2),
          ),
        );
        break;
    }
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
        SnackBar(content: Text(friendlyError(error))),
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
        SnackBar(content: Text(friendlyError(error))),
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

  /// This account's plan, from the server's own billing columns. A trial counts,
  /// and a stale `pro` label cannot outlive its period.
  ///
  /// One source for every chart gate — replay, the Pro candle sizes and the
  /// position objects — so no two of them can disagree about what is owned.
  Future<SubscriptionInfo?> _subscription() async {
    try {
      final profile = await JournalApi().profile();
      return SubscriptionInfo.fromProfile(profile);
    } catch (_) {
      // Offline, or a schema still missing the billing columns: null, so each
      // caller answers no rather than pretending the feature is paid for.
      return null;
    }
  }

  /// Whether this account holds Pro right now.
  Future<bool> _hasProTools() async =>
      (await _subscription())?.proTools ?? false;

  /// Whether the chart's paid objects are open: a live trial or any paid plan.
  ///
  /// The position objects are sold with Basic, so this asks the wider question
  /// `_hasProTools` does not: Basic pays for pinning levels, Pro pays for the
  /// analysis on top of it.
  Future<bool> _hasPaidPlan() async =>
      (await _subscription())?.hasAccess ?? false;

    /// Whether this candle size is part of the account's plan.
  ///
  /// 5s/10s/15s are Pro, 30s and 45s are Basic, and the free chart runs from a
  /// minute up — the same split the web desk uses (`isTimeframeOpen` in
  /// `src/lib/subscription.ts`). A refused size says which plan would open it,
  /// because the sheet deliberately keeps every size visible.
  Future<bool> _intervalAllowed(ChartInterval interval) async {
    final pro = isProTimeFrame(interval);
    if (!pro && !isBasicTimeFrame(interval)) return true;

    final plan = await _subscription();
    final allowed = pro ? (plan?.proTools ?? false) : (plan?.hasAccess ?? false);
    if (allowed) return true;

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pro
              ? '5s, 10s and 15s candles are a Pro feature. Basic charts run from 30s up.'
              : '30s and 45s candles are part of Basic. Free charts run from 1m up.',
        ),
      ),
    );
    return false;
  }

  /// The position objects pin entry, stop and target to the chart.
  ///
  /// Unlike replay and the fast candle sizes this is a Basic feature, not a Pro
  /// one, which is why it reads `_hasPaidPlan` and not `_hasProTools`.
  Future<bool> _pinAllowed() async {
    if (await _hasPaidPlan()) return true;

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pinning entry, stop and target on the chart is part of Basic. '
          'Upgrade to pin your levels — the chart itself and every other '
          'drawing tool stay free.',
        ),
      ),
    );
    return false;
  }

  /// Replay is sold with Pro.
  ///
  /// This check is the upgrade prompt, not the enforcement: candles are served
  /// to every plan, and replay is a way of drawing on them. It lives here
  /// because entering replay is the only moment a trader discovers the feature.
  Future<bool> _replayAllowed() async {
    if (await _hasProTools()) return true;

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
    final l10n = AppLocalizations.of(context);
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
                // The handle is the sheet's "this is dismissible" cue; without
                // it a dark panel running to both edges reads as a page rather
                // than a sheet laid over the chart.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      l10n.chartToolsTitle,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.closeAction,
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
                  l10n.chartToolsBody,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                DrawingsPanel(
                  onPick: pick,
                  keepDrawing: _keepDrawing,
                  onKeepDrawingChanged: (value) =>
                      setState(() => _keepDrawing = value),
                  magnet: _magnet,
                  onMagnetChanged: _setMagnet,
                ),
                if (hasSelection) ...[
                  const SizedBox(height: 14),
                  _sheetLabel(l10n.selectedObject),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _toolCard(
                          icon: Icons.edit_outlined,
                          label: l10n.objectEdit,
                          subtitle: l10n.objectEditSub,
                          onTap: () => pick('edit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _toolCard(
                          icon: Icons.copy_all_outlined,
                          label: l10n.objectClone,
                          subtitle: l10n.objectCloneSub,
                          onTap: () => pick('clone'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _toolCard(
                          icon: Icons.delete_outline,
                          label: l10n.objectDelete,
                          subtitle: l10n.objectDeleteSub,
                          tone: AppColors.danger,
                          onTap: () => pick('delete'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                _sheetLabel(l10n.manageSection),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.undo, size: 20),
                  title: Text(l10n.undoLast),
                  enabled: _drawings.isNotEmpty,
                  onTap: () => pick('undo'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.redo, size: 20),
                  title: Text(l10n.redoAction),
                  enabled: _redo.isNotEmpty,
                  onTap: () => pick('redo'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_tree_outlined, size: 20),
                  title: Text(l10n.objectTree),
                  enabled: _drawings.isNotEmpty,
                  onTap: () => pick('tree'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.more_horiz, size: 20),
                  title: Text(l10n.analysisHub),
                  subtitle: Text(l10n.analysisHubSub),
                  onTap: () => pick('hub'),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_sweep_outlined, size: 20),
                  title: Text(l10n.clearDrawings),
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
    //
    // They are also the two objects that pin entry, stop and target to the
    // chart, and pinning is sold with Basic. Everything else on this screen —
    // every other tool, and every candle size but the Pro seconds — is free, so
    // the refusal is here, at the tap, and names the plan: a free trader should
    // learn what the object costs rather than find it silently skipped.
    if (action == 'long' || action == 'short') {
      if (!await _pinAllowed()) return;
      _armTool(
        DrawingKind.position,
        side: action == 'long' ? PositionSide.long : PositionSide.short,
      );
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
    if (action == 'hub') {
      await _openAnalysisHub();
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
    required VoidCallback? onTap,
    Color? tone,
  }) {
    // A card with nowhere to go still draws, greyed: a hub that hides its
    // unavailable tools leaves the trader wondering whether it has them at all.
    final color = onTap == null ? AppColors.faint : (tone ?? AppColors.text);
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
    // The lock is the whole point: with it on, the tool stays armed so the next
    // press starts the next object of the same kind.
    if (!_keepDrawing) _disarmTool();
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
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
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
  ///
  /// Style and label travel with it: a clone of a dashed red zone is a dashed
  /// red zone. Lock and hide do not — the copy is a working object, and one that
  /// cannot be grabbed or seen would look like the clone failed.
  ChartDrawing _nudgedCopy(ChartDrawing source) {
    final last = _lastVisible;
    final base = last?.close ?? source.entry ?? source.startPrice;
    final nudge = _defaultRisk(base) * 0.3;
    final look = source.look.copyWith(locked: false, hidden: false);

    final copy = switch (source.kind) {
      DrawingKind.ray => ChartDrawing.ray(
          look: look,
          price: (source.price ?? base) + nudge,
        ),
      DrawingKind.trend => ChartDrawing.trend(
          look: look,
          startMs: source.startMs,
          startPrice: source.startPrice + nudge,
          endMs: source.endMs,
          endPrice: source.endPrice + nudge,
        ),
      DrawingKind.position => ChartDrawing.position(
          look: look,
          side: source.side ?? PositionSide.long,
          startMs: source.startMs,
          endMs: source.endMs,
          entry: (source.entry ?? base) + nudge,
          stop: (source.stop ?? base) + nudge,
          target: (source.target ?? base) + nudge,
        ),
      _ => ChartDrawing.points(
          look: look,
          kind: source.kind,
          text: source.text,
          points: [
            for (final point in source.points)
              ChartPoint(ms: point.ms, price: point.price + nudge),
          ],
        ),
    };
    return copy.withEditedAt(DateTime.now().millisecondsSinceEpoch);
  }

  void _cloneDrawing(int index) {
    if (index < 0 || index >= _drawings.length) return;
    _addDrawing(_nudgedCopy(_drawings[index]));
  }

  String _drawingTitle(ChartDrawing drawing) {
    switch (drawing.kind) {
      case DrawingKind.ray:
        if (drawing.look.alert) {
          return drawing.look.fired ? 'Alert line — fired' : 'Alert line';
        }
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
    final decimals = _decimals;
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
                (item) =>
                    item.id == drawing.id &&
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
                            onPressed: () => Navigator.of(sheetContext).pop(),
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
                              color:
                                  item.look.hidden ? AppColors.faint : item.ink,
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
                                  tooltip: item.look.locked ? 'Unlock' : 'Lock',
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

  /// The object's settings: how it looks, exactly where it sits, what it says,
  /// and the actions that belong with it. Everything is a draft until Ok, so
  /// Cancel really cancels — a widened box comes back the width it was.
  Future<void> _editDrawing(int index) async {
    if (index < 0 || index >= _drawings.length) return;
    final drawing = _drawings[index];
    final result = await showObjectSettings(
      context,
      drawing: drawing,
      title: _drawingTitle(drawing),
      decimals: _decimals,
    );
    if (!mounted || result == null) return;

    if (result.remove) {
      _deleteDrawing(index);
      return;
    }

    final changed = result.drawing;
    if (changed == null) return;
    // Stamped now, at the moment the trader pressed Ok, so the other device
    // compares against the edit rather than against when the sheet opened.
    final stamped = changed.withEditedAt(DateTime.now().millisecondsSinceEpoch);

    if (result.clone) {
      _addDrawing(_nudgedCopy(stamped));
      return;
    }

    final next = [..._drawings];
    // Visual order is the list's own order — last painted sits on top — so
    // bringing to front is a move to the end, not a z-index the painter has to
    // learn about.
    if (result.order == null) {
      next[index] = stamped;
    } else {
      next.removeAt(index);
      if (result.order == ObjectOrder.front) {
        next.add(stamped);
      } else {
        next.insert(0, stamped);
      }
    }
    final moved = next.indexOf(stamped);
    setState(() {
      _drawings = next;
      _selectedDrawing = moved >= 0 ? moved : null;
    });
    _persistDrawings(next);
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
    final decimals = _decimals;
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

  /// The analysis hub: workspace controls above, analytical tools below.
  ///
  /// This is the "..." button of a charting app — the place a trader goes to
  /// change how they are looking rather than what they are looking at. Cards
  /// rather than rows, because the six workspace actions are the ones people
  /// hit without reading.
  Future<void> _openAnalysisHub() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final active = _layouts
            .where((layout) => layout.id == _activeLayoutId)
            .cast<ChartLayout?>()
            .firstWhere((layout) => layout != null, orElse: () => null);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      AppLocalizations.of(sheetContext).analysisHub,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: AppLocalizations.of(sheetContext).closeAction,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                    ),
                  ],
                ),
                Text(
                  active == null
                      ? 'No layout saved yet — Save keeps this chart exactly as it looks.'
                      : 'Layout: ${active.name}',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _sheetLabel('WORKSPACE'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _toolCard(
                        icon: Icons.dashboard_customize_outlined,
                        label: 'Layouts',
                        subtitle: '${_layouts.length} saved',
                        onTap: () => Navigator.of(sheetContext).pop('layouts'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.tune,
                        label: 'Settings',
                        subtitle: _style.name,
                        onTap: () => Navigator.of(sheetContext).pop('settings'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.save_outlined,
                        label: 'Save',
                        subtitle: 'This chart',
                        onTap: () => Navigator.of(sheetContext).pop('save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _toolCard(
                        icon: Icons.folder_open_outlined,
                        label: 'Open',
                        subtitle: 'From library',
                        onTap: () => Navigator.of(sheetContext).pop('open'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.note_add_outlined,
                        label: 'New',
                        subtitle: 'Blank chart',
                        onTap: () => Navigator.of(sheetContext).pop('new'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.grid_view_outlined,
                        label: 'Type',
                        subtitle: _style.chartType.label,
                        onTap: () => Navigator.of(sheetContext).pop('type'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _sheetLabel('TOOLS'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _toolCard(
                        icon: Icons.show_chart,
                        label: 'Indicators',
                        subtitle: _style.studies.isEmpty
                            ? 'None'
                            : '${_style.studies.length} on',
                        onTap: () =>
                            Navigator.of(sheetContext).pop('indicators'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.notifications_active_outlined,
                        label: 'Alerts',
                        subtitle: 'Level touches',
                        onTap: () => Navigator.of(sheetContext).pop('alerts'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.replay,
                        label: 'Replay',
                        subtitle: _replay == null ? 'Off' : 'On',
                        onTap: _candles.length < 12
                            ? null
                            : () => Navigator.of(sheetContext).pop('replay'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _toolCard(
                        icon: Icons.account_tree_outlined,
                        label: 'Object tree',
                        subtitle: '${_drawings.length} objects',
                        onTap: _drawings.isEmpty
                            ? null
                            : () => Navigator.of(sheetContext).pop('tree'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.schedule,
                        label: 'Time zone',
                        subtitle: _style.zone.describe(),
                        onTap: () => Navigator.of(sheetContext).pop('zone'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _toolCard(
                        icon: Icons.calendar_month_outlined,
                        label: 'Events',
                        subtitle: _eventsSummary(_style),
                        onTap: () => Navigator.of(sheetContext).pop('events'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'layouts':
      case 'open':
        await _openLayouts();
        break;
      case 'save':
        await _saveLayout();
        break;
      case 'new':
        await _newLayout();
        break;
      case 'settings':
        await _openStyleSheet();
        break;
      case 'indicators':
      case 'studies':
        await _openStyleSheet(start: _SettingsPage.indicators);
        break;
      case 'zone':
        final zone = await _pickZone(_style.zone);
        if (zone == null || !mounted) return;
        setState(() => _style = _style.copyWith(zoneId: zone.id));
        unawaited(ChartStyle.save());
        unawaited(ChartStyle.saveLayout(widget.instrument.symbol, _style));
        break;
      case 'alerts':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
        );
        break;
      case 'replay':
        _toggleReplayMode();
        break;
      case 'tree':
        await _openObjectTree();
        break;
      case 'events':
        await _openStyleSheet(start: _SettingsPage.events);
        break;
      case 'type':
        await _openStyleSheet(start: _SettingsPage.appearance);
        break;
    }
  }

  /// The saved-layout library, loaded once per visit and kept in memory: the
  /// list is small and the manager edits it locally before a single write.
  List<ChartLayout> _layouts = const <ChartLayout>[];
  String? _activeLayoutId;

  Future<void> _restoreLayouts() async {
    final layouts = await ChartLayoutStore.load();
    final active = await ChartLayoutStore.activeId();
    if (!mounted) return;
    setState(() {
      _layouts = layouts;
      _activeLayoutId = active;
    });
  }

  /// Saves what is on screen as a layout, under a name the trader picks.
  ///
  /// Saving over the active layout is the common case — a chart is tuned a
  /// little at a time — so the dialog offers that name first and keeps its id,
  /// which is what makes "Save" an update instead of a growing pile.
  Future<void> _saveLayout() async {
    final existing = _layouts
        .where((layout) => layout.id == _activeLayoutId)
        .cast<ChartLayout?>()
        .firstWhere((layout) => layout != null, orElse: () => null);
    final controller = TextEditingController(
      text: existing?.name ?? '${widget.instrument.symbol} ${_interval.key}',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Save layout' : 'Update layout'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Layout name',
            hintText: 'JeyMTL',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(existing == null ? 'Save' : 'Update'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;

    final saved = ChartLayout(
      id: existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      name: name,
      symbol: widget.instrument.symbol,
      intervalKey: _interval.key,
      style: _style,
      savedAt: DateTime.now(),
      starred: existing?.starred ?? false,
    );
    final next = <ChartLayout>[
      for (final layout in _layouts)
        if (layout.id != saved.id) layout,
      saved,
    ];
    await ChartLayoutStore.save(next);
    await ChartLayoutStore.setActive(saved.id);
    if (!mounted) return;
    setState(() {
      _layouts = next;
      _activeLayoutId = saved.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved “$name”.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Opens the library and applies whatever the trader picks.
  Future<void> _openLayouts() async {
    if (_layouts.isEmpty) await _restoreLayouts();
    if (!mounted) return;
    final result = await showLayoutsManager(
      context,
      layouts: _layouts,
      activeId: _activeLayoutId,
      currentSymbol: widget.instrument.symbol,
      currentIntervalKey: _interval.key,
    );
    if (!mounted || result == null) return;

    if (result.saveCurrent) {
      await _saveLayout();
      return;
    }
    final deleting = result.delete;
    if (deleting != null) {
      final next =
          _layouts.where((layout) => layout.id != deleting.id).toList();
      await ChartLayoutStore.save(next);
      final active = _activeLayoutId == deleting.id ? null : _activeLayoutId;
      await ChartLayoutStore.setActive(active);
      if (!mounted) return;
      setState(() {
        _layouts = next;
        _activeLayoutId = active;
      });
      return;
    }

    final layout = result.layout;
    if (layout == null) return;
    final interval = ChartInterval.values.firstWhere(
      (candidate) => candidate.key == layout.intervalKey,
      orElse: () => _interval,
    );
    final candlesChanged = interval != _interval;
    setState(() {
      _style = layout.style;
      _activeLayoutId = layout.id;
    });
    unawaited(ChartStyle.save());
    unawaited(ChartStyle.saveLayout(widget.instrument.symbol, layout.style));
    unawaited(ChartLayoutStore.setActive(layout.id));
    // The candle size is a different series, so it is switched through the one
    // path that already clears the cache, the replay and the stale stamp.
    if (candlesChanged) await _setInterval(interval);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          layout.symbol == widget.instrument.symbol
              ? 'Opened “${layout.name}”.'
              : 'Opened “${layout.name}” on ${widget.instrument.symbol} — the '
                  'palette and candle size came with it.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// A blank chart: the app's own palette, no studies, no active layout.
  Future<void> _newLayout() async {
    setState(() {
      _style = ChartStyle.ink;
      _activeLayoutId = null;
    });
    unawaited(ChartStyle.save());
    unawaited(ChartStyle.saveLayout(widget.instrument.symbol, ChartStyle.ink));
    unawaited(ChartLayoutStore.setActive(null));
  }

  Future<void> _openStyleSheet(
      {_SettingsPage start = _SettingsPage.canvas}) async {
    var page = start;
    // Everything below edits a draft. Nothing reaches the chart until Ok, which
    // is the whole point of a Cancel button: a trader tries a light canvas, sees
    // it is wrong and walks away with the dark one still there.
    var draft = _style;
    // The account's copy first, then the device's: a look saved on the web desk
    // should be in this list before the trader scrolls it.
    final synced =
        await ChartTemplatesSync().sync(await ChartPresetStore.load());
    final presets = synced.presets;
    if (synced.changed) unawaited(ChartPresetStore.save(presets));
    if (!mounted) return;

    void commit(ChartStyle next) {
      ChartStyle.current = next;
      unawaited(ChartStyle.save());
      unawaited(ChartStyle.saveLayout(widget.instrument.symbol, next));
      if (!mounted) return;
      setState(() => _style = next);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.94,
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return _styleSheet(
                draft,
                (next) => setSheetState(() => draft = next),
                page: page,
                onNavigate: (next) => setSheetState(() => page = next),
                onClose: () => Navigator.of(sheetContext).pop(),
                onTemplates: () => _openTemplates(
                  presets: presets,
                  onApply: (next) => setSheetState(() => draft = next),
                  onSaveAs: () async {
                    final name = await _namePreset();
                    if (name == null || name.isEmpty || !mounted) return;
                    final saved = ChartPreset(
                      name: name,
                      style: draft,
                      editedAtMs: DateTime.now().millisecondsSinceEpoch,
                    );
                    presets
                      ..removeWhere(
                        (preset) =>
                            preset.name.toLowerCase() == name.toLowerCase(),
                      )
                      ..insert(0, saved);
                    await ChartPresetStore.save(presets);
                    // The account copy is best-effort: the template is already
                    // safe on this device.
                    unawaited(ChartTemplatesSync().push(saved));
                    if (!mounted) return;
                    setSheetState(() {});
                  },
                  onDeletePreset: (preset) async {
                    presets.removeWhere((item) => item.name == preset.name);
                    await ChartPresetStore.save(presets);
                    unawaited(ChartTemplatesSync().remove(preset));
                    if (!mounted) return;
                    setSheetState(() {});
                  },
                ),
                footer: _settingsFooter(
                  onCancel: () => Navigator.of(sheetContext).pop(),
                  onOk: () {
                    commit(draft);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// The fixed bar at the base of the sheet: Cancel and Apply, the same width
  /// each, 48pt tall. Nothing here is a shortcut — the arrow goes back to the
  /// chart unchanged, the gold button commits the draft.
  Widget _settingsFooter({
    required VoidCallback onCancel,
    required VoidCallback onOk,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppColors.text,
                side: BorderSide(color: AppColors.borderStrong),
              ),
              child: const Text('Cancel', maxLines: 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: onOk,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Apply', maxLines: 1),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTemplates({
    required List<ChartPreset> presets,
    required ValueChanged<ChartStyle> onApply,
    required Future<void> Function() onSaveAs,
    required Future<void> Function(ChartPreset preset) onDeletePreset,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                leading: const Icon(Icons.restart_alt, size: 20),
                title: const Text('Apply defaults'),
                subtitle:
                    const Text('Back to the app’s own palette and studies'),
                onTap: () {
                  onApply(ChartStyle.ink);
                  Navigator.of(sheetContext).pop();
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.save_as_outlined, size: 20),
                title: const Text('Save as…'),
                subtitle: const Text('Keep these settings as a template'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await onSaveAs();
                },
              ),
              if (presets.isNotEmpty) ...[
                const Divider(height: 8),
                for (final preset in presets)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.dashboard_outlined, size: 20),
                    title: Text(preset.name),
                    trailing: IconButton(
                      tooltip: 'Delete ${preset.name}',
                      onPressed: () async {
                        await onDeletePreset(preset);
                        if (context.mounted) setLocal(() {});
                      },
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppColors.danger,
                      ),
                    ),
                    onTap: () {
                      onApply(preset.style);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _namePreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save template'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: 'Template name',
            hintText: 'MTL',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  /// The chart settings sheet. The pages are tabs across the top rather than a
  /// list of groups, so any setting is one tap from the chart, and the sheet
  /// never opens on a screen with nothing on it.
  Widget _styleSheet(
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged, {
    required _SettingsPage page,
    required ValueChanged<_SettingsPage> onNavigate,
    required VoidCallback onClose,
    required VoidCallback onTemplates,
    required Widget footer,
  }) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _settingsHeader(onClose: onClose, onTemplates: onTemplates),
          _SettingsTabs(page: page, onNavigate: onNavigate),
          Flexible(child: _settingsBody(page, style, onChanged)),
          footer,
        ],
      ),
    );
  }

  String _eventsSummary(ChartStyle style) {
    final parts = <String>[
      if (style.showSessions) 'Sessions',
      if (style.showSeparators) '${style.separatorGrain.label} lines',
    ];
    return parts.isEmpty ? 'Off' : parts.join(' · ');
  }

  Widget _settingsHeader({
    required VoidCallback onClose,
    required VoidCallback onTemplates,
  }) {
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
            padding: const EdgeInsets.fromLTRB(20, 2, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Chart settings',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Templates',
                  onPressed: onTemplates,
                  icon: Icon(
                    Icons.dashboard_customize_outlined,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsBody(
    _SettingsPage page,
    ChartStyle style,
    ValueChanged<ChartStyle> onChanged,
  ) {
    switch (page) {
      case _SettingsPage.alerts:
        return _alertsSettings(style, onChanged);
      case _SettingsPage.canvas:
        return _canvasSettings(style, onChanged);
      case _SettingsPage.symbol:
        return _symbolSettings(style, onChanged);
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
    }
  }

  /// Alert lines: what colour they take when they point up or down, and
  /// whether the ones that have already fired stay in view.
  Widget _alertsSettings(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Alert lines'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _colorRow(
            'Above the market',
            style.alertUp ?? style.bull,
            (color) => onChanged(style.copyWith(alertUp: color)),
          ),
        ),
        _settingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _colorRow(
            'Below the market',
            style.alertDown ?? style.bear,
            (color) => onChanged(style.copyWith(alertDown: color)),
          ),
        ),
        _settingsDivider(),
        _settingsSwitch(
          'Only active alerts',
          subtitle: 'Lines that have already fired are kept but taken off the '
              'chart, so what is left is what is still being watched.',
          value: style.onlyActiveAlerts,
          onChanged: (value) =>
              onChanged(style.copyWith(onlyActiveAlerts: value)),
        ),
        _settingsGroupLabel('On the chart'),
        _settingsRow(
          title: 'Add an alert',
          subtitle: 'Long-press the chart, then tap + beside the price and '
              'choose “Add alert”.',
          value: 'Crosshair +',
        ),
      ],
    );
  }

  /// The canvas itself: what it is painted on, and how the crosshair reads
  /// against it.
  Widget _canvasSettings(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    final stop = style.backgroundTo;
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Background'),
        _settingsSwitch(
          'Gradient',
          subtitle: 'The canvas falls from the theme colour to a second one, '
              'which keeps a tall chart from reading as a slab.',
          value: stop != null,
          onChanged: (value) => onChanged(
            value
                ? style.copyWith(backgroundTo: _gradientStop(style.background))
                : style.copyWith(clearBackgroundTo: true),
          ),
        ),
        if (stop != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _colorRow('Bottom colour', stop, (color) {
              onChanged(style.copyWith(backgroundTo: color));
            }),
          ),
          _settingsDivider(),
        ],
        _settingsGroupLabel('Crosshair'),
        _settingsControlRow(
          'Style',
          _segmented(
            selected: style.crosshairStyle,
            options: [
              for (final option in CrosshairStyle.values)
                (value: option, label: option.label),
            ],
            onSelect: (option) =>
                onChanged(style.copyWith(crosshairStyle: option)),
          ),
        ),
        _settingsDivider(),
        _settingsRow(
          title: 'Thickness',
          subtitle: 'How heavy the crosshair rules are, in pixels.',
          value: '${style.crosshairWidth.toStringAsFixed(0)} px',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final width in const [1.0, 2.0, 3.0, 4.0])
                _StylePill(
                  label: '${width.toStringAsFixed(0)} px',
                  selected: style.crosshairWidth == width,
                  onTap: () => onChanged(style.copyWith(crosshairWidth: width)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A second background colour that is a step off the theme's own: lighter on
  /// a dark canvas, darker on a light one, so the gradient never fights the
  /// candles before the trader has chosen one.
  Color _gradientStop(Color base) {
    final toward = base.computeLuminance() > 0.5
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    return Color.lerp(base, toward, 0.08)!;
  }

  /// What the bars are made of, and how many decimals every price on the chart
  /// prints. The two belong together: both decide how much of the market is
  /// visible at a glance rather than how it is painted.
  Widget _symbolSettings(ChartStyle style, ValueChanged<ChartStyle> onChanged) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _settingsGroupLabel('Bars'),
        _settingsSwitch(
          'Colour bars by previous close',
          subtitle: 'A bar that closes where the last one did stays neutral '
              'instead of flipping colour.',
          value: style.colorBarsByPrevClose,
          onChanged: (value) =>
              onChanged(style.copyWith(colorBarsByPrevClose: value)),
        ),
        _settingsDivider(),
        _settingsSwitch(
          'Body',
          subtitle: 'Off leaves just the wick, which is how a bar chart is '
              'read.',
          value: style.showCandleBody,
          onChanged: (value) =>
              onChanged(style.copyWith(showCandleBody: value)),
        ),
        _settingsDivider(),
        _settingsSwitch(
          'Border',
          subtitle: 'A one-pixel edge around each body.',
          value: style.showCandleBorder,
          onChanged: (value) =>
              onChanged(style.copyWith(showCandleBorder: value)),
        ),
        _settingsDivider(),
        _settingsSwitch(
          'Wick',
          subtitle: 'The high–low line through the body.',
          value: style.showCandleWick,
          onChanged: (value) =>
              onChanged(style.copyWith(showCandleWick: value)),
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
        _settingsGroupLabel('Precision'),
        _settingsRow(
          title: 'Decimal places',
          subtitle: 'Every price on this chart prints with this many decimals. '
              'The instrument decides when left on default.',
          value: style.precision == null
              ? 'Default (${widget.instrument.decimals})'
              : '${style.precision}',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StylePill(
                label: 'Default',
                selected: style.precision == null,
                onTap: () => onChanged(style.copyWith(clearPrecision: true)),
              ),
              for (var places = 0; places <= 8; places++)
                _StylePill(
                  label: '$places',
                  selected: style.precision == places,
                  onTap: () => onChanged(style.copyWith(precision: places)),
                ),
            ],
          ),
        ),
      ],
    );
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
                  // A theme is colours, not tools: the magnet the trader set
                  // survives picking a new palette.
                  onTap: () => onChanged(preset.copyWith(magnet: style.magnet)),
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
        _settingsRow(
          title: 'Candle colours and precision',
          subtitle: 'Per-bar colours, body/wick switches and decimals live '
              'under Symbol.',
          value: 'Symbol',
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
        _settingsDivider(),
        _settingsSwitch(
          'Countdown to bar close',
          subtitle: 'Under the last price: how long this candle still has to '
              'run.',
          value: style.showCountdown,
          onChanged: (value) => onChanged(style.copyWith(showCountdown: value)),
        ),
        _settingsGroupLabel('Time axis'),
        _settingsSwitch(
          'Day of week on labels',
          subtitle: '“Fri 20 Nov” rather than “20 Nov”.',
          value: style.dayOfWeekLabels,
          onChanged: (value) =>
              onChanged(style.copyWith(dayOfWeekLabels: value)),
        ),
        _settingsDivider(),
        _settingsSwitch(
          '24-hour clock',
          subtitle: 'Off prints 11:50 PM instead of 23:50, on the axis and in '
              'the crosshair badge.',
          value: style.use24Hour,
          onChanged: (value) => onChanged(style.copyWith(use24Hour: value)),
        ),
        _settingsDivider(),
        _settingsSwitch(
          'Axis “+” button',
          subtitle: 'The circular button beside the crosshair price, for '
              'alerts and horizontal lines on that price.',
          value: style.showAxisPlus,
          onChanged: (value) => onChanged(style.copyWith(showAxisPlus: value)),
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
      trailing: _TogglePill(value: value, onChanged: onChanged),
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
                    last == null
                        ? '—'
                        : chartPrice(last, instrument, decimals: _decimals),
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
              IconButton(
                tooltip:
                    _crosshairMode ? 'Crosshair mode on' : 'Crosshair mode off',
                onPressed: () =>
                    setState(() => _crosshairMode = !_crosshairMode),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 30,
                ),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.center_focus_strong,
                  size: 17,
                  color:
                      _crosshairMode ? AppColors.primaryLight : AppColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              // Expanded instead of Spacer: the timestamp is the part that has
              // to give way when the pills and a doubled text size leave no
              // room, and a Spacer only reports the overflow.
              Expanded(
                // The OHLC readout lives in the chart's own header bar now, so
                // this strip keeps the one thing that bar cannot say: when the
                // candles last arrived.
                child: _updated == null
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
    // The seconds sizes are sold, and split across the paid plans. The picker
    // lists them either way; the refusal happens here so the answer names the
    // plan instead of switching to a size the feed would serve but the account
    // has not paid for.
    final picked = choice.interval;
    if (picked != null && !await _intervalAllowed(picked)) return;
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
            price == null
                ? '—'
                : chartPrice(price, instrument, decimals: _decimals),
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
    this.keepDrawing = false,
    this.crosshairMode = false,
    this.onFinishPlacement,
    required this.onDrawingCreated,
    this.magnet = MagnetMode.weak,
    this.onPlacing,
    this.onQuickAction,
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
  /// While one is set the canvas stops panning and starts placing: a drag
  /// sizes the object and lifts to finish, while two taps set its two anchors.
  final DrawingKind? pendingKind;
  final PositionSide? pendingSide;

  /// Keep the armed tool armed after a valid object is committed.
  final bool keepDrawing;

  /// One-finger drags scrub the crosshair instead of panning.
  final bool crosshairMode;

  /// Put the tool away from the floating Done pill.
  final VoidCallback? onFinishPlacement;

  /// A placed object, finished and ready for the screen to keep.
  final ValueChanged<ChartDrawing> onDrawingCreated;

  /// Snap a placed or dragged point onto a wick, open, high, low or close.
  final MagnetMode magnet;

  /// The candle under the crosshair, or null when the crosshair is away. The
  /// screen uses it for the O H L C legend in the header.

  /// True once the finger has put down the first point of the object being
  /// placed, so the banner can count.
  final ValueChanged<bool>? onPlacing;

  /// The price and candle time under a crosshair the trader is acting on. The
  /// screen owns what the actions do, because they reach past the canvas.
  final void Function(double price, DateTime time)? onQuickAction;

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

  /// True when the crosshair was left behind by a long press, so the trader can
  /// lift their finger and still act on the price it is showing.
  bool _crosshairPinned = false;

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

  /// The price the stop or target line was on at the previous drag frame, so a
  /// tick fires when it crosses a level rather than on every pixel of travel.
  double? _dragTickedAt;
  Offset _tapDownAt = Offset.zero;
  Offset _doubleTapAt = Offset.zero;
  DateTime _tapDownTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// A two-anchor object has to be at least this wide in screen pixels before
  /// it is committed; anything smaller is a stray tap, not a drawing.
  static const double _minDrawingSpan = 12;

  /// Movement past this many pixels is a drag, not a tap.
  static const double _dragSlop = 8;

  /// The live coordinate readout while a handle is held.
  DrawingDragFeedback? _dragFeedback;
  List<ChartPoint> _brush = const [];
  double _baseSpan = 0;
  double _baseStart = 0;

  /// Manual vertical offset of the price window, as a share of the visible
  /// range. Zero is auto-fit, which is what the chart does by default; dragging
  /// up or down moves the price axis without touching the time axis, the way a
  /// desktop terminal does.
  double _pricePan = 0;

  /// Vertical magnification of the price window. 1 is auto-fit; a two-finger
  /// vertical spread stretches the range, and a pinch compresses it, which is
  /// how a 30-pip move is read on a phone screen.
  double _priceZoom = 1;
  double _basePriceZoom = 1;

  /// Which axis strip this gesture started on. A drag along the price column
  /// or the timestamp strip zooms that axis instead of panning the chart, the
  /// way the same strips behave in a desktop terminal.
  _AxisDrag _axisDrag = _AxisDrag.none;
  Offset _axisDragDelta = Offset.zero;

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

  /// Counts the clock down under the last price. Ticks only while the trader
  /// has the countdown switched on, so a chart without it never wakes the
  /// device once a second for a number nobody is reading.
  Timer? _countdown;
  DateTime _now = DateTime.now();

  void _syncCountdown() {
    final wanted = widget.style.showCountdown && widget.candles.isNotEmpty;
    if (wanted && _countdown == null) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!wanted) {
      _countdown?.cancel();
      _countdown = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncLevels();
    _view.fit(widget.candles.length);
    _rebuildStudies();
    _syncCountdown();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _settle.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCountdown();
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
        _priceZoom = 1;
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

    // The vertical stretch happens around the middle of the pane, so pinching
    // magnifies what the trader is looking at instead of sliding it away.
    if (_priceZoom != 1) {
      final mid = (low + high) / 2;
      final half = (high - low) / 2 / _priceZoom;
      low = mid - half;
      high = mid + half;
    }

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
    final ms = chartTimeMsForX(
      dx: local.dx,
      candles: widget.candles,
      interval: widget.interval.size,
      start: _view.start,
      span: _view.span,
      plotW: plotW,
    );
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
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
    if (widget.magnet == MagnetMode.off) return raw;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    final candles = widget.candles;
    if (plotW <= 0 || candles.isEmpty) return raw;
    final chartW = chartCandleWidth(plotW);
    // In the future gutter there is no candle to snap to yet.
    if (chartW <= 0 || local.dx > chartW) return raw;
    final ratio = (local.dx / chartW).clamp(0.0, 1.0).toDouble();
    final index = _view.indexAt(ratio, candles.length);
    final prices = <double>[
      for (var i = math.max(0, index - 1);
          i <= math.min(candles.length - 1, index + 1);
          i++) ...<double>[
        candles[i].open,
        candles[i].high,
        candles[i].low,
        candles[i].close,
      ],
    ];
    return magnetPrice(
      raw: raw,
      candidates: magnetCandidates(
        prices: prices,
        yFor: _yFor,
        fingerY: local.dy,
      ),
      mode: widget.magnet,
    );
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
    final dx = math.min(chartCandleWidth(plotW) * 0.3, 120.0);
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
      _lastTouch = local;
      _crosshairPinned = false;
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
    final moved = (local - from).distance > _dragSlop;
    setState(() {
      _lastTouch = local;
      if (kind == DrawingKind.brush && moved) {
        _brush = [..._brush, _pointAt(local)];
      }
      _crosshair = local;
      _preview = _draftFor(kind, from, local, sized: moved);
    });
  }

  /// Two anchors, one tap each. A tap that lands too close to the first point
  /// is thrown away rather than committed as an invisible sliver.
  bool _needsSecondPoint(DrawingKind kind) =>
      kind != DrawingKind.ray &&
      kind != DrawingKind.vline &&
      kind != DrawingKind.text &&
      kind != DrawingKind.arrowUp &&
      kind != DrawingKind.arrowDown;

  void _commitPlace({bool force = false}) {
    final placed = _preview;
    final from = _placeFrom;
    final span = from == null ? double.infinity : (_lastTouch - from).distance;
    final needsSpan = placed != null && _needsSecondPoint(placed.kind);
    if (needsSpan && !force && span < _minDrawingSpan) {
      // Discard the draft, but keep the tool armed: the next tap starts a
      // fresh first point instead of leaving a zero-width ghost behind.
      setState(() {
        _preview = null;
        _placeFrom = null;
        _brush = const [];
        _crosshair = null;
        _crosshairPinned = false;
      });
      widget.onPlacing?.call(false);
        return;
    }
    setState(() {
      _preview = null;
      _placeFrom = null;
      _brush = const [];
      _crosshair = null;
      _crosshairPinned = false;
    });
    widget.onPlacing?.call(false);
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
      _crosshair = null;
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
    // A handle's 24px touch target is bigger than the body's 14px one; a press
    // near a corner has to grab the handle even when it is outside the stroke.
    if (_handleAt(drawing, local, plotW) != null) return true;
    final distance = _drawingDistance(drawing, local, plotW);
    return distance != null && distance <= 14;
  }

  double? _xForTime(int ms, double plotW) => chartXForTimeMs(
        ms: ms,
        candles: widget.candles,
        interval: widget.interval.size,
        start: _view.start,
        span: _view.span,
        plotW: plotW,
      );

  double _anchorX(int ms, double plotW) => _xForTime(ms, plotW) ?? 0;

  /// The draggable dots of an object: its anchors, or a trend line's two ends.
  List<Offset> _anchorsOf(ChartDrawing drawing, double plotW) {
    if (drawing.kind == DrawingKind.trend) {
      final start = _xForTime(drawing.startMs, plotW);
      final end = _xForTime(drawing.endMs, plotW);
      if (start == null || end == null) return const [];
      return [
        Offset(start, _yFor(drawing.startPrice)),
        Offset(end, _yFor(drawing.endPrice)),
      ];
    }
    if (!drawing.isAnchored) return const [];
    return [
      for (final point in drawing.points)
        Offset(_anchorX(point.ms, plotW), _yFor(point.price)),
    ];
  }

  /// Shapes that have a centre node for moving the whole object.
  bool _hasCentreHandle(DrawingKind kind) => switch (kind) {
        DrawingKind.rectangle ||
        DrawingKind.ellipse ||
        DrawingKind.fib ||
        DrawingKind.fibExtension ||
        DrawingKind.measure =>
          true,
        _ => false,
      };

  /// Which anchor a press has taken hold of, or -1 for the centre move node.
  ///
  /// Handle hit-testing is deliberately much wider than the drawn dot: a 5px
  /// dot is a marker, not a touch target, and missing it turns a resize into a
  /// pan.
  int? _handleAt(ChartDrawing drawing, Offset local, double plotW) {
    final anchors = _anchorsOf(drawing, plotW);
    int? best;
    var bestDistance = 24.0;
    for (var i = 0; i < anchors.length; i++) {
      final distance = (anchors[i] - local).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    if (best == null && _hasCentreHandle(drawing.kind) && anchors.length >= 2) {
      var left = anchors.first.dx;
      var right = anchors.first.dx;
      var top = anchors.first.dy;
      var bottom = anchors.first.dy;
      for (final anchor in anchors.skip(1)) {
        left = math.min(left, anchor.dx);
        right = math.max(right, anchor.dx);
        top = math.min(top, anchor.dy);
        bottom = math.max(bottom, anchor.dy);
      }
      final centre = Offset((left + right) / 2, (top + bottom) / 2);
      if ((centre - local).distance <= 24) return -1;
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
    // A clean tap is short and still. A longer or travelling touch is a pan
    // that the gesture recogniser happened to classify as a tap.
    final clean = (local - _tapDownAt).distance < _dragSlop &&
        DateTime.now().difference(_tapDownTime) <
            const Duration(milliseconds: 250);
    if (!clean) return;
    // An armed tool owns the tap. One-point tools land immediately; two-anchor
    // tools take a first point, then a second, and refuse a second point that
    // would make an invisible sliver.
    final kind = widget.pendingKind;
    if (kind != null) {
      _lastTouch = local;
      if (!_needsSecondPoint(kind)) {
        if (_preview == null) _beginPlace(local);
        _commitPlace(force: true);
        return;
      }
      final from = _placeFrom;
      if (from == null) {
        _beginPlace(local);
        return;
      }
      setState(() {
        _preview = _draftFor(kind, from, local, sized: true);
      });
      _commitPlace();
      return;
    }
    // A tap anywhere is a decision about something else, so a crosshair left
    // behind by a long press goes away with it.
    if (_crosshairPinned) {
      setState(() {
        _crosshairPinned = false;
        _crosshair = null;
      });
    }
    final panes = TradingChartPainter.paneLayout(_size.height, widget.style);
    final inPricePane =
        local.dy >= panes.priceTop && local.dy <= panes.priceTop + panes.priceH;

    // A tap can only ever select something. Tools place their own object when
    // they are picked, so a stray tap never starts a point.
    if (inPricePane) {
      final hit = _nearestDrawing(local);
      if (hit != null) {
        // Selection shows the handles and the top bar. The bottom sheet is a
        // deliberate second step — More, Edit, or a double tap.
        widget.onDrawingSelected(hit);
        return;
      }
    }
    // Nothing else happens on a tap: levels are set by dragging their handles
    // or by editing the fields below the chart, never by an accidental touch.
    if (widget.selectedDrawing != null) widget.onDrawingSelected(null);
  }

  void _onScaleStart(ScaleStartDetails details) {
    // A new touch owns the chart: stop the coast where it is, and put a pinned
    // crosshair away — the trader has moved on to something else.
    _settle.stop();
    if (_crosshairPinned) {
      setState(() {
        _crosshairPinned = false;
        _crosshair = null;
      });
    }
    _lastTouch = details.localFocalPoint;
    // Every gesture keeps these, so a pinch that starts on an object still has
    // the viewport it began with when it takes over.
    _baseSpan = _view.span;
    _baseStart = _view.start;
    _basePriceZoom = _priceZoom;
    _axisDragDelta = Offset.zero;
    _axisDrag = _AxisDrag.none;
    if (widget.pendingKind != null) {
      final from = _placeFrom;
      if (from == null) {
        _beginPlace(details.localFocalPoint);
      } else {
        setState(() {
          _preview = _draftFor(
            widget.pendingKind!,
            from,
            details.localFocalPoint,
            sized: false,
          );
          _crosshair = details.localFocalPoint;
        });
      }
      return;
    }
    // A selected object is grabbed directly: press on it and drag. An
    // unselected object is selected by a clean tap, so its body cannot steal a
    // pan from the chart.
    if (_hitsSelected(details.localFocalPoint)) {
      _startDrag(details.localFocalPoint);
      return;
    }
    if (details.pointerCount == 1) {
      final plotW = _size.width - TradingChartPainter.axisWidth;
      final point = details.localFocalPoint;
      if (plotW > 0 && point.dx >= plotW) {
        _axisDrag = _AxisDrag.price;
      } else if (point.dy >= _size.height - TradingChartPainter.bottomPad) {
        _axisDrag = _AxisDrag.time;
      }
    }
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
    // A drag sizes the object and commits on lift-off; a still press leaves it
    // in 2 of 2, waiting for a deliberate second tap rather than dropping a
    // zero-width shape where the finger happened to rest.
    if (_placeFrom != null) {
      final moved = (_lastTouch - _placeFrom!).distance;
      if (moved < _dragSlop) {
        final kind = widget.pendingKind;
        if (kind != null) {
          setState(() {
            _preview = _draftFor(kind, _placeFrom!, _placeFrom!, sized: false);
            _crosshair = _placeFrom;
          });
        }
        return;
      }
      _commitPlace();
      return;
    }
    if (_drawingIndex != null) {
      _endDrag(_lastTouch);
      return;
    }
    // A pinned crosshair survives the lift-off that follows its long press; a
    // pan or pinch has already put it away. In crosshair mode the finished
    // position stays put, which is what a desk does.
    if (!_crosshairPinned && !widget.crosshairMode) {
      setState(() => _crosshair = null);
    }
    // A zoom drag ends where the finger lifts: there is no throw to hand on.
    if (_axisDrag != _AxisDrag.none) {
      _axisDrag = _AxisDrag.none;
      return;
    }
    final count = widget.candles.length;
    if (count < 2 || _dragging != null || _drawingIndex != null) return;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (plotW <= 0) return;

    // Finger moving right moves the chart right, which walks the window back.
    final chartW = chartCandleWidth(plotW);
    if (chartW <= 0) return;
    final perSecond =
        -details.velocity.pixelsPerSecond.dx / chartW * _view.span;
    if (perSecond.abs() < 4) {
      // Too slow to be a throw: just sit on the nearest bar.
      _animateStartTo(_view.start.roundToDouble(), 120);
      return;
    }
    _animateStartTo(_view.flingRest(perSecond, count), 420, thenSnap: true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // A second finger outranks everything: cancel a half-finished object drag
    // or drawing, drop the crosshair, and give the gesture to pinch-zoom and
    // pan. Object mutation never survives a pinch.
    if (details.pointerCount >= 2) {
      if (_drawingIndex != null) _abortDrawingDrag();
      if (_placeFrom != null) _cancelPlace();
      if (_dragging != null) setState(() => _dragging = null);
    } else {
      if (_placeFrom != null) {
        _updatePlace(details.localFocalPoint);
        return;
      }
      if (_drawingIndex != null) {
        _lastTouch = details.localFocalPoint;
        _updateDrag(details.localFocalPoint);
        return;
      }
    }
    if (widget.candles.length < 2) return;
    final plotW = _size.width - TradingChartPainter.axisWidth;
    if (plotW <= 0) return;
    final chartW = chartCandleWidth(plotW);
    if (chartW <= 0) return;
    final ratio =
        (details.localFocalPoint.dx / chartW).clamp(0.0, 1.0).toDouble();
    final showCrosshair = widget.crosshairMode && details.pointerCount < 2;
    setState(() {
      if (details.pointerCount >= 2) {
        _view.zoomAround(
          scale: details.scale,
          anchorRatio: ratio,
          count: widget.candles.length,
          baseSpan: _baseSpan,
          baseStart: _baseStart,
        );
        // A diagonal pinch scales both axes at once: the finger decides, and
        // there is no modifier to reach for on a phone.
        if ((details.verticalScale - 1).abs() > 0.005) {
          _priceZoom = (_basePriceZoom * details.verticalScale)
              .clamp(0.2, 8.0)
              .toDouble();
        }
      } else if (_axisDrag != _AxisDrag.none) {
        _axisDragDelta += details.focalPointDelta;
        if (_axisDrag == _AxisDrag.time) {
          // Along the timestamp strip, right pulls more history into view and
          // left widens the bars, with the newest bar held in place so the
          // live edge does not walk out from under the trader.
          _view.zoomAround(
            scale: timeAxisDragZoom(_axisDragDelta.dx / chartW),
            anchorRatio: 1,
            count: widget.candles.length,
            baseSpan: _baseSpan,
            baseStart: _baseStart,
          );
        } else {
          final panes = TradingChartPainter.paneLayout(
            _size.height,
            widget.style,
          );
          if (panes.priceH > 0) {
            // Up the price column stretches the scale around the middle of the
            // pane; down compresses it. Same clamp as a two-finger spread so
            // the two gestures cannot disagree.
            _priceZoom = (_basePriceZoom *
                    axisDragZoom(
                      _axisDragDelta.dy / panes.priceH,
                      invert: true,
                    ))
                .clamp(0.2, 8.0)
                .toDouble();
          }
        }
      } else {
        _view.pan(-details.focalPointDelta.dx / chartW * _view.span);
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
      _crosshair = showCrosshair ? details.localFocalPoint : null;
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
        xs.add(_anchorX(point.ms, plotW));
        ys.add(_yFor(point.price));
      }
      final left = xs.reduce(math.min);
      var right = xs.reduce(math.max);
      // The projected part of a rectangle is part of the object, so it has to
      // be selectable too.
      if (drawing.look.extendRight && drawing.kind == DrawingKind.rectangle) {
        right = math.max(right, plotW);
      }
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
      // An anchor older than the loaded window draws from the left edge, so a
      // tap anywhere on the box still finds it. A future end projects into the
      // gutter and is grabbable there.
      final left = _xForTime(drawing.startMs, plotW) ?? 0;
      if (local.dx < left - 12) return null;
      final endMs = drawing.endMs > 0
          ? drawing.endMs
          : widget.candles.last.time.millisecondsSinceEpoch;
      final right = _xForTime(endMs, plotW) ?? plotW;
      if (local.dx > right + 12) return null;
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
    final start = _xForTime(drawing.startMs, plotW);
    final end = _xForTime(drawing.endMs, plotW);
    if (start == null || end == null) return null;
    final a = Offset(start, _yFor(drawing.startPrice));
    var b = Offset(end, _yFor(drawing.endPrice));
    // A line extended right is grabbable along its projection, not only on the
    // stretch between its two anchors.
    if (drawing.look.extendRight && b.dx > a.dx + 0.5) {
      final slope = (b.dy - a.dy) / (b.dx - a.dx);
      b = Offset(plotW, a.dy + slope * (plotW - a.dx));
    }
    return _distanceToSegment(local, a, b);
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
    // -1 is the centre move node: it translates the object, exactly as a drag
    // on the body does, rather than replacing an anchor.
    if (handle != null && handle >= 0) {
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
    final chartW = chartCandleWidth(plotW);
    final barMs = widget.interval.size.inMilliseconds;
    final shiftBars = chartW <= 0 || barMs <= 0
        ? 0
        : ((local.dx - _dragOrigin.dx) / chartW * _view.span).round();
    final candles = widget.candles;
    // Time follows whole bars, in either direction: an object dragged past the
    // newest candle keeps a future timestamp instead of being clamped to it.
    int shiftTime(int ms) => ms + shiftBars * barMs;

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
    // Only the selected object captures a press. An unselected object is
    // selected by a clean tap; its body does not steal a drag from the chart.
    final selected = widget.selectedDrawing;
    if (selected != null &&
        selected >= 0 &&
        selected < widget.drawings.length &&
        _hitsSelected(local)) {
      _beginDrawingDrag(selected, local);
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

  void _beginDrawingDrag(int index, Offset local) {
    final original = widget.drawings[index];
    if (original.look.locked) {
      widget.onDrawingSelected(index);
      return;
    }
    final plotW = _size.width - TradingChartPainter.axisWidth;
    setState(() {
      _crosshair = null;
      _dragFeedback = null;
      _drawingIndex = index;
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
    widget.onDrawingSelected(index);
  }

  PositionLevel? _dragLevel;

  /// True while the finger holds the position box's right grip.
  bool _dragEdge = false;

  bool _nearRightEdge(ChartDrawing drawing, Offset local, double plotW) {
    if (!drawing.isPosition || widget.candles.isEmpty) return false;
    final endMs = drawing.endMs > 0
        ? drawing.endMs
        : widget.candles.last.time.millisecondsSinceEpoch;
    final right = _xForTime(endMs, plotW);
    if (right == null) return false;
    return (local.dx - right).abs() <= 24;
  }

  /// Restores the object the drag started from, then ends the drag. Used when
  /// a second finger turns the gesture into a pinch.
  void _abortDrawingDrag() {
    final index = _drawingIndex;
    final original = _drawingOriginal;
    if (index != null && original != null) {
      widget.onDrawingMoved(index, original);
    }
    setState(() {
      _drawingIndex = null;
      _drawingOriginal = null;
      _dragLevel = null;
      _dragEdge = false;
      _dragHandle = null;
      _dragFeedback = null;
    });
    widget.onDrawingMoveEnd();
  }

  void _updateDrag(Offset local) {
    _lastTouch = local;
    final drawing = _drawingOriginal;
    final index = _drawingIndex;
    if (drawing != null && index != null) {
      final point = _pointAt(local);
      setState(() {
        _crosshair = null;
        _dragFeedback = _dragHandle == null
            ? null
            : DrawingDragFeedback(
                price: point.price,
                ms: point.ms,
                touch: local,
              );
      });
      widget.onDrawingMoved(index, _movedDrawing(drawing, local));
      return;
    }
    final marker = _dragging;
    if (marker == null) {
      setState(() => _crosshair = local);
      return;
    }
    final price = _priceFor(local);
    // Dragging a stop or a target across the entry, or across the other one of
    // the pair, is where the risk flips sign. A tick marks the crossing.
    if (marker == Marker.stop || marker == Marker.take) {
      final anchor = marker == Marker.stop ? _stop : _take;
      final previous = _dragTickedAt;
      if (previous != null) {
        for (final level in [
          if (marker != Marker.entry) _entry,
          if (marker != Marker.stop) _stop,
          if (marker != Marker.take) _take,
        ]) {
          if (level == null || level == anchor) continue;
          final before = previous - level;
          final after = price - level;
          if (before != 0 && after != 0 && before.sign != after.sign) {
            HapticFeedback.selectionClick();
            break;
          }
        }
      }
    }
    _dragTickedAt = price;
    setState(() {
      _setDraft(marker, price);
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
        _dragFeedback = null;
      });
      widget.onDrawingMoveEnd();
      return;
    }
    final marker = _dragging;
    _dragTickedAt = null;
    // A long press that did not grab anything leaves the crosshair where the
    // trader put it. TradingView keeps it too: the price it is on is the thing
    // the next tap acts on, and clearing it on lift-off would make the quick
    // actions beside it unreachable.
    if (marker == null && _crosshair != null) {
      setState(() => _crosshairPinned = true);
      return;
    }
    setState(() {
      _dragging = null;
      _crosshair = null;
      _crosshairPinned = false;
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
    // The OHLC legend gets a slim strip above the plot instead of a chip on the
    // canvas. Drawn on top it sat under the target badge at the top of the range
    // and over the bar being measured, which is the one thing the trader is
    // looking at while a level is pinned.
    const header = 24.0;
    // Sized rather than Expanded: a caller can hand this a short box, and a
    // negative flex is a layout crash rather than a small chart.
    final plotHeight = math.max(0.0, height - header - 0.6);
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: widget.style.background,
        child: Column(
          children: [
            SizedBox(
              height: header,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  6,
                  2,
                  TradingChartPainter.axisWidth,
                  2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IgnorePointer(child: _readout()),
                ),
              ),
            ),
            Container(height: 0.6, color: widget.style.axis),
            SizedBox(
              height: plotHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              _tapDownAt = details.localPosition;
              _tapDownTime = DateTime.now();
            },
            onTapUp: (details) => _tap(details.localPosition),
            // A double tap on an object opens its full menu; anywhere else it
            // restores auto-fit, which is the gesture a trader reaches for
            // after stretching the axis by mistake.
            onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
            onDoubleTap: () {
              final hit = _nearestDrawing(_doubleTapAt);
              if (hit != null) {
                widget.onDrawingSelected(hit);
                widget.onDrawingTapped(hit);
                return;
              }
              setState(() {
                _pricePan = 0;
                _priceZoom = 1;
              });
            },
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
                      now: _now,
                      interval: widget.interval,
                      chartType: widget.style.chartType,
                      studies: _studies,
                      drawings: widget.drawings,
                      selectedDrawing: widget.selectedDrawing,
                      positionOutcomes: widget.positionOutcomes,
                      preview: _preview,
                      dragFeedback: _dragFeedback,
                      style: widget.style,
                      symbol: widget.symbol,
                    ),
                  ),
                ),
                // The quick-action button sits on the price the crosshair is
                // showing, exactly where the eye already is. It only exists
                // while there is a crosshair to act on, and only when the
                // trader has not switched it off under Settings → Scales.
                if (_crosshair != null && widget.style.showAxisPlus)
                  Positioned(
                    right: TradingChartPainter.axisWidth + 2,
                    top: (_crosshair!.dy - 12).clamp(0.0, _size.height - 24),
                    child: Semantics(
                      button: true,
                      label: 'Quick actions at this price',
                      child: GestureDetector(
                        onTap: () {
                          final price = _priceFor(_crosshair!);
                          final time = _timeFor(_crosshair!) ?? DateTime.now();
                          widget.onQuickAction?.call(price, time);
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: widget.style.background.withAlpha(235),
                            shape: BoxShape.circle,
                            border: Border.all(color: widget.style.axis),
                          ),
                          child: Icon(
                            Icons.add,
                            size: 16,
                            color: widget.style.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                // A shifted price axis: the same affordance as LIVE, so the
                // trader is never stuck with a scale they cannot undo.
                if (_pricePan != 0 || _priceZoom != 1)
                  Positioned(
                    right: TradingChartPainter.axisWidth + 6,
                    bottom: 34,
                    child: Semantics(
                      button: true,
                      label: 'Fit the price scale',
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _pricePan = 0;
                          _priceZoom = 1;
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
                // With Keep drawing on, the tool stays armed after a commit.
                // A floating Done gives the trader an obvious way out without
                // hunting for the bin in the placement banner.
                if (widget.keepDrawing && widget.pendingKind != null)
                  Positioned(
                    left: 0,
                    right: TradingChartPainter.axisWidth,
                    bottom: 8,
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: 'Finish drawing',
                        child: GestureDetector(
                          onTap: widget.onFinishPlacement,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: drawingColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check,
                                  size: 15,
                                  color: widget.style.background,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Done',
                                  style: TextStyle(
                                    color: widget.style.background,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _readout() {
    final plotW = _size.width - TradingChartPainter.axisWidth;
    final chartW = chartCandleWidth(plotW);
    final ratio = _crosshair == null || chartW <= 0
        ? 1.0
        : (_crosshair!.dx / chartW).clamp(0.0, 1.0).toDouble();
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

    // No pill any more: it is a bar, not an overlay, so the text sits on the
    // canvas background and only the candle colours distinguish it.
    return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${widget.interval.key}  ',
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

/// Which axis a drag is zooming, when it started on a strip rather than the
/// plotting area.
enum _AxisDrag { none, time, price }

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

/// The switch of the settings pages: a 46pt pill with a white thumb, gold
/// when on. Reachable at 46pt wide, which the platform switch drawn at 28pt
/// inside a FittedBox was not.
class _TogglePill extends StatelessWidget {
  const _TogglePill({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value ? AppColors.primary : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: value ? AppColors.primary : AppColors.borderStrong,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 140),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The settings tab strip: icons over short names, scrolling sideways because
/// ten tabs are wider than a phone. The selected tab carries the gold rule and
/// the strip scrolls it into view when a page is opened from a chart shortcut.
class _SettingsTabs extends StatefulWidget {
  const _SettingsTabs({required this.page, required this.onNavigate});

  final _SettingsPage page;
  final ValueChanged<_SettingsPage> onNavigate;

  @override
  State<_SettingsTabs> createState() => _SettingsTabsState();
}

class _SettingsTabsState extends State<_SettingsTabs> {
  final Map<_SettingsPage, GlobalKey> _keys = {
    for (final page in _SettingsPage.values) page: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _reveal(widget.page, animate: false);
  }

  @override
  void didUpdateWidget(_SettingsTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _reveal(widget.page, animate: true);
  }

  void _reveal(_SettingsPage page, {required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[page]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // The strip is as tall as its tallest label, not a fixed 54: at 2x text the
    // names grow and a fixed height clips the icon or the second line.
    final labelHeight = MediaQuery.textScalerOf(context).scale(11.5) * 1.3;
    return Container(
      height: math.max(54, 18 + 3 + labelHeight + 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final page in _SettingsPage.values)
            _SettingsTab(
              key: _keys[page],
              page: page,
              selected: page == widget.page,
              onTap: () => widget.onNavigate(page),
            ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    super.key,
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final _SettingsPage page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(page.icon, size: 18, color: color),
            const SizedBox(height: 3),
            Text(
              page.title,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
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
        width: 32,
        height: 32,
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
  symbol('Symbol', Icons.style_outlined),
  canvas('Canvas', Icons.layers_outlined),
  appearance('Appearance', Icons.palette_outlined),
  scales('Scales', Icons.straighten),
  grid('Grid', Icons.grid_4x4),
  watermark('Watermark', Icons.branding_watermark_outlined),
  alerts('Alerts', Icons.notifications_active_outlined),
  events('Events', Icons.event_note_outlined),
  indicators('Indicators', Icons.show_chart),
  timeZone('Time zone', Icons.schedule);

  const _SettingsPage(this.title, this.icon);

  final String title;
  final IconData icon;
}
