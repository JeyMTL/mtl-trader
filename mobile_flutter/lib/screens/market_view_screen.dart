import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/features.dart';
import '../core/market_widget.dart';
import '../ui/theme.dart';

/// Market view: prices by TradingView, in TradingView's own WebView.
///
/// This replaces the desk chart on the phone while the app has no feed it can
/// legally draw (`kMarketChartsEnabled`). It is deliberately not a chart of the
/// trader's own market data: nothing here touches the journal, the API or the
/// candle route, so it cannot show a quote we are not licensed to serve.
///
/// The instrument and size pickers are native, not TradingView's toolbar: the
/// phone is a thumb's reach wide, and a WebView toolbar at 3x text size is where
/// this would otherwise become unusable.
///
/// Rotated, the screen drops every line of chrome it can — title, description,
/// footer, chip rows — and leaves the chart the whole frame. The controls that
/// stay sit in one 38-point strip above it, because covering the chart's own
/// legend is the one thing a full-screen chart must not do.
class MarketViewScreen extends StatefulWidget {
  const MarketViewScreen({super.key, this.instrument});

  /// The symbol the trader was already looking at, if any. It only decides which
  /// chip opens selected; the view still maps it through the pinned table.
  final String? instrument;

  @override
  State<MarketViewScreen> createState() => _MarketViewScreenState();
}

class _MarketViewScreenState extends State<MarketViewScreen> {
  late String _instrument = marketInstrumentFor(widget.instrument);
  MarketInterval _interval = kMarketIntervals[2];
  bool _light = false;
  late final WebViewController _web = _buildController();

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF131722))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            // The widget itself and the TradingView pages it links to stay in
            // place; a broker or a social link opens in the browser, because a
            // WebView with someone else's page in it is a phishing surface.
            if (uri.host == 'tradingview.com' ||
                uri.host.endsWith('.tradingview.com')) {
              return NavigationDecision.navigate;
            }
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(_uri());
  }

  Uri _uri() => marketViewUri(
        symbol: tradingViewSymbol(_instrument) ?? 'FX:EURUSD',
        interval: _interval,
        light: _light,
      );

  /// The chip row, with a searched-for symbol put in front when the shortlist
  /// does not carry it — otherwise the chart shows one thing and no chip agrees.
  List<String> get _instruments => kMarketInstruments.contains(_instrument)
      ? kMarketInstruments
      : <String>[_instrument, ...kMarketInstruments];

  void _select(String instrument) {
    if (instrument == _instrument) return;
    setState(() => _instrument = instrument);
    unawaited(_web.loadRequest(_uri()));
  }

  void _selectInterval(MarketInterval interval) {
    if (interval.key == _interval.key) return;
    setState(() => _interval = interval);
    unawaited(_web.loadRequest(_uri()));
  }

  void _toggleTheme() {
    setState(() => _light = !_light);
    unawaited(_web.loadRequest(_uri()));
  }

  Future<void> _openSearch() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InstrumentSearch(selected: _instrument),
    );
    if (chosen != null && mounted) _select(chosen);
  }

  @override
  Widget build(BuildContext context) {
    // Literal English, like the chart and the trade form it sits beside: those
    // screens have not been moved onto language packs yet, and an ARB key would
    // have to be filled in all 33 packs before the l10n test went green.
    if (!kMarketWidgetEnabled) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Market view')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'The market view is switched off in this build.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45),
            ),
          ),
        ),
      );
    }

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (landscape) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _landscapeBar(),
              Expanded(child: WebViewWidget(controller: _web)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Market view'),
        actions: [
          IconButton(
            tooltip: _light ? 'Dark chart' : 'Light chart',
            onPressed: _toggleTheme,
            icon: Icon(
              _light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 20,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Text(
              'Live market prices from TradingView. This is not your journal and '
              "not your broker's feed — a free public chart while the journaled "
              'chart is offline.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: _SearchBar(
              hint: 'Search pairs and currencies',
              onTap: _openSearch,
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _instruments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final code = _instruments[index];
                return _Chip(
                  label: marketInstrumentLabel(code),
                  selected: code == _instrument,
                  onTap: () => _select(code),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _intervalChips(),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: WebViewWidget(controller: _web),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 12, color: AppColors.faint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Prices are supplied by TradingView and may be delayed or '
                    "indicative. Your broker's executable price is the one in "
                    'your terminal.',
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 10.5,
                      height: 1.35,
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

  /// One strip: the symbol (with search), the sizes, the theme. Everything else
  /// the portrait screen explains is a tap away behind the search sheet, so the
  /// chart is the frame rather than a panel inside it.
  Widget _landscapeBar() {
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 2),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _SearchBar(
                hint: marketInstrumentLabel(_instrument),
                onTap: _openSearch,
                compact: true,
                value: true,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 6,
              child: SizedBox(height: 30, child: _intervalChips()),
            ),
            IconButton(
              tooltip: _light ? 'Dark chart' : 'Light chart',
              onPressed: _toggleTheme,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 30),
              icon: Icon(
                _light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 17,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intervalChips() => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kMarketIntervals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final interval = kMarketIntervals[index];
          return _Chip(
            label: interval.label,
            selected: interval.key == _interval.key,
            onTap: () => _selectInterval(interval),
          );
        },
      );
}

/// A search field that opens the instrument sheet.
///
/// Not a live text field: the sheet has the real one, with the keyboard and the
/// results, and a field here would need both at once. This reads as a search bar
/// so the way in is where a trader looks for it.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.hint,
    required this.onTap,
    this.compact = false,
    this.value = false,
  });

  final String hint;
  final VoidCallback onTap;
  final bool compact;

  /// Whether `hint` is the current instrument rather than a placeholder, so it
  /// is drawn as text rather than as a hint.
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: value ? 'Instrument $hint, search' : 'Search instruments',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Container(
          height: compact ? 30 : 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: compact ? 15 : 17,
                color: value ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value ? AppColors.primaryLight : AppColors.muted,
                    fontSize: compact ? 11.5 : 12.5,
                    fontWeight: value ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The instrument sheet: every chip, plus any pair or alias the mapping can
/// resolve and the chips do not carry.
class _InstrumentSearch extends StatefulWidget {
  const _InstrumentSearch({required this.selected});

  final String selected;

  @override
  State<_InstrumentSearch> createState() => _InstrumentSearchState();
}

class _InstrumentSearchState extends State<_InstrumentSearch> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = marketInstrumentMatches(_query.text);
    final typed = _query.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search pairs and currencies',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                        child: Text(
                          'No market view for “$typed”. The pairs here are the '
                          'ones TradingView publishes; anything else stays in '
                          'your terminal.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final code = results[index];
                          final selected = code == widget.selected;
                          return ListTile(
                            dense: true,
                            title: Text(
                              marketInstrumentLabel(code),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color:
                                    selected ? AppColors.primaryLight : null,
                              ),
                            ),
                            subtitle: Text(
                              code,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check,
                                    size: 18, color: AppColors.primary)
                                : null,
                            onTap: () => Navigator.of(context).pop(code),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withAlpha(28) : AppColors.surface,
            border: Border.all(
              color: selected ? AppColors.primary.withAlpha(140) : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primaryLight : AppColors.muted,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
