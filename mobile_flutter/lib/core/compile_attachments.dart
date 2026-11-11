import 'dart:convert';
import 'dart:typed_data';

/// Limits for the charts sent with a custom backtest compile.
///
/// They mirror `/api/backtest/compile`: four images, 4 MB each, and a 3 MB
/// ceiling on the whole set because the JSON body (base64 adds a third) has a
/// platform cap. Kept a little under the server's budget so a screenshot taken
/// at the edge does not turn into a refused compile after the trader has typed a
/// paragraph.
const int maxCompileCharts = 4;
const int maxCompileChartBytes = 4 * 1024 * 1024;
const int compileChartBudgetBytes = 2800000;

/// Formats the vision model actually accepts. HEIC from an iPhone picker is not
/// one, and the server drops it without telling the app; refusing it here means
/// the trader knows the chart was not sent.
const Set<String> compileImageMimes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

/// One chart screenshot, already encoded for the JSON request.
class CompileChart {
  const CompileChart({
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.dataUrl,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String dataUrl;

  int get size => bytes.length;
}

/// Some pickers report `image/jpg`, which is the same format under its old
/// spelling; the server only lists `image/jpeg`.
String _imageMime(String mimeType) {
  final mime = mimeType.toLowerCase().split(';').first.trim();
  return mime == 'image/jpg' ? 'image/jpeg' : mime;
}

/// Why this picture cannot join the set, or null when it can.
///
/// [usedBytes] is the decoded size of the charts already attached; [count] is
/// how many there are. The returned sentence is written for the trader and shown
/// beside the picker.
String? chartRejection({
  required int count,
  required int usedBytes,
  required int candidateBytes,
  required String mimeType,
}) {
  if (!compileImageMimes.contains(_imageMime(mimeType))) {
    return 'Use a PNG, JPEG or WebP screenshot.';
  }
  if (count >= maxCompileCharts) {
    return 'Up to $maxCompileCharts charts.';
  }
  if (candidateBytes > maxCompileChartBytes) {
    return 'That screenshot is over 4 MB. Crop it to the setup.';
  }
  if (usedBytes + candidateBytes > compileChartBudgetBytes) {
    return 'Those charts are too large to send together. Remove one, or crop it.';
  }
  return null;
}

/// `data:image/png;base64,…` for the compile request, or null for a format the
/// model does not accept.
String? chartDataUrl(String mimeType, Uint8List bytes) {
  final mime = _imageMime(mimeType);
  if (!compileImageMimes.contains(mime) || bytes.isEmpty) return null;
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

/// `data:audio/mp4;base64,…` for the transcription request.
String audioDataUrl(String mimeType, Uint8List bytes) =>
    'data:${mimeType.toLowerCase()};base64,${base64Encode(bytes)}';
