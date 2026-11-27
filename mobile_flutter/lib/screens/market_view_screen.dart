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
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: kMarketInstruments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final code = kMarketInstruments[index];
                final selected = code == _instrument;
                return _Chip(
                  label: marketInstrumentLabel(code),
                  selected: selected,
                  onTap: () => _select(code),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
