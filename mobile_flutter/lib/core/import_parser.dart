import 'dart:convert';
import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

/// A trade read from an MT5 or broker history export.
///
/// Mirrors `ParsedTrade` in `src/lib/import-parser.ts` so an import on the phone
/// writes the same columns as one on the web desk.
class ParsedTrade {
  /// Rebuilds a trade from the server parser's JSON, used for workbooks the
  /// phone cannot decode itself (legacy `.xls`).
  factory ParsedTrade.fromMap(Map<String, dynamic> map) {
    double number(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    final ticket = map['ticket'];
    return ParsedTrade(
      symbol: '${map['symbol'] ?? ''}'.toUpperCase(),
      type: '${map['type'] ?? ''}'.toUpperCase(),
      entry: number(map['entry']),
      exit: number(map['exit']),
      lot: number(map['lot']),
      pnl: number(map['pnl']),
      commission: number(map['commission']),
      swap: number(map['swap']),
      date: '${map['date'] ?? ''}',
      closeDate: '${map['closeDate'] ?? ''}',
      sl: number(map['sl']),
      tp: number(map['tp']),
      ticket: ticket is num ? ticket.toInt() : int.tryParse('$ticket'),
    );
  }

  const ParsedTrade({
    required this.symbol,
    required this.type,
    required this.entry,
    required this.exit,
    required this.lot,
    required this.pnl,
    required this.commission,
    required this.swap,
    required this.date,
    required this.closeDate,
    required this.sl,
    required this.tp,
    this.ticket,
  });

  final String symbol;

  /// `BUY` or `SELL`, already upper-cased and validated.
  final String type;
  final double entry;
  final double exit;
  final double lot;

  /// Net of commission and swap, like the web importer.
  final double pnl;
  final double commission;
  final double swap;

  /// ISO-ish local timestamps, or an empty string when the export has none.
  final String date;
  final String closeDate;
  final double sl;
  final double tp;
  final int? ticket;
}

String normalizeHeader(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

double parseNumeric(String value) {
  if (value.trim().isEmpty) return 0;
  final raw = value
      .trim()
      .replaceAll(RegExp(r'[ currency$€£]', caseSensitive: false), '');
  final value2 = raw
      .replaceAllMapped(RegExp(r'^\((.*)\)$'), (m) => '-${m[1]}')
      .replaceAll(RegExp(r'\s'), '');
  if (value2.isEmpty) return 0;
  final String normalized;
  if (value2.contains(',') && value2.contains('.')) {
    normalized = value2.lastIndexOf(',') > value2.lastIndexOf('.')
        ? value2.replaceAll('.', '').replaceAll(',', '.')
        : value2.replaceAll(',', '');
  } else {
    normalized = value2.replaceAll(',', '.');
  }
  return double.tryParse(normalized) ?? 0;
}

int? parseTicket(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final ticket = int.tryParse(digits);
  return ticket == null || ticket <= 0 ? null : ticket;
}

/// The app convention is negative = paid. MT5 already exports negative costs;
/// brokers that export positive ones are flipped.
double normalizeSignedCost(double value) => value > 0 ? -value : value;

String normalizeDate(String value) {
  final s = value.trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase();
  if (lower.contains('running') || lower.contains('open')) return '';

  final iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?',
  ).firstMatch(s);
  if (iso != null) {
    return '${iso[1]}-${iso[2]}-${iso[3]}T${iso[4]}:${iso[5]}:${iso[6] ?? '00'}';
  }

  final mt5 = RegExp(
    r'^(\d{4})\.(\d{2})\.(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  if (mt5 != null) {
    return '${mt5[1]}-${mt5[2]}-${mt5[3]}T${mt5[4]}:${mt5[5]}:${mt5[6] ?? '00'}';
  }

  final us = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  if (us != null) {
    final isoDate = _isoDate(us[3]!, us[1]!, us[2]!);
    if (isoDate != null) return '${isoDate}T${us[4]}:${us[5]}:${us[6] ?? '00'}';
  }

  final dateOnly = RegExp(r'^(\d{4})[.-](\d{2})[.-](\d{2})$').firstMatch(s);
  if (dateOnly != null) {
    return '${dateOnly[1]}-${dateOnly[2]}-${dateOnly[3]}T00:00:00';
  }

  final usDateOnly =
      RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
  if (usDateOnly != null) {
    final isoDate = _isoDate(usDateOnly[3]!, usDateOnly[1]!, usDateOnly[2]!);
    if (isoDate != null) return '${isoDate}T00:00:00';
  }

  return s;
}

/// `MM/DD/YYYY` to `YYYY-MM-DD`, or null when the numbers are not a date.
String? _isoDate(String year, String month, String day) {
  final y = int.parse(year);
  final m = int.parse(month);
  final d = int.parse(day);
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  return '$year-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// Comma, semicolon or tab, counted outside quotes over the first lines.
String detectDelimiter(String text) {
  final lines = const LineSplitter()
      .convert(text)
      .where((line) => line.trim().isNotEmpty)
      .take(20);
  final counts = <String, int>{',': 0, ';': 0, '\t': 0};
  for (final line in lines) {
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && counts.containsKey(ch)) {
        counts[ch] = counts[ch]! + 1;
      }
    }
  }
  var best = ',';
  var bestCount = -1;
  counts.forEach((delimiter, count) {
    if (count > bestCount) {
      bestCount = count;
      best = delimiter;
    }
  });
  return best;
}

/// A small RFC 4180 reader: quoted fields may contain the delimiter, newlines
/// and doubled quotes.
List<List<String>> parseDelimited(String text, {String delimiter = ','}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delimiter) {
      row.add(field.toString().trim());
      field.clear();
    } else if (ch == '\n') {
      row.add(field.toString().trim());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  row.add(field.toString().trim());
  if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
  return rows;
}

/// Read a CSV/TSV/txt export, an MT5 SpreadsheetML report or an Excel workbook
/// into rows of cell text.
///
/// The formats match the web desk's importer, so the same file imports the same
/// way on both.
List<List<String>> parseFileRows(String fileName, Uint8List bytes) {
  final lowerName = fileName.toLowerCase();

  // A workbook is a zip (or, for the old BIFF format, an OLE container), so the
  // extension is only a hint — the bytes decide.
  final isWorkbook = lowerName.endsWith('.xlsx') ||
      lowerName.endsWith('.xls') ||
      (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) ||
      (bytes.length >= 4 &&
          bytes[0] == 0xd0 &&
          bytes[1] == 0xcf &&
          bytes[2] == 0x11 &&
          bytes[3] == 0xe0);
  if (isWorkbook) {
    final rows = _spreadsheetRows(bytes);
    if (rows.isNotEmpty) return rows;
  }

  final looksLikeXml = lowerName.endsWith('.xml') ||
      (bytes.length >= 5 &&
          bytes[0] == 0x3c &&
          bytes[1] == 0x3f &&
          bytes[2] == 0x78 &&
          bytes[3] == 0x6d &&
          bytes[4] == 0x6c);

  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) text = text.substring(1);
  if (text.trim().isEmpty) return const [];

  if (looksLikeXml ||
      RegExp(r'^\s*<\?xml', caseSensitive: false).hasMatch(text) ||
      text.contains('xmlns:html2="urn:report-component')) {
    final rows = xmlStringToRows(text);
    if (rows.isNotEmpty) return rows;
  }

  return parseDelimited(text, delimiter: detectDelimiter(text));
}

/// Flatten the first sheet of an Excel workbook. Cells arrive as text, numbers
/// or ISO timestamps; everything is narrowed to the text the column map and the
/// number/date parsers already understand.
List<List<String>> _spreadsheetRows(Uint8List bytes) {
  final decoder = SpreadsheetDecoder.decodeBytes(bytes);
  if (decoder.tables.isEmpty) return const [];
  return [
    for (final row in decoder.tables.values.first.rows)
      [for (final cell in row) cell == null ? '' : cell.toString().trim()],
  ];
}

/// First `<tag ...>...</tag>` block (or a self-closing tag) at or after [from].
({String attrs, String inner, int next})? _matchTag(
  String text,
  String tag,
  int from,
) {
  final open = text.indexOf('<$tag', from);
  if (open == -1) return null;
  final attrsEnd = text.indexOf('>', open);
  if (attrsEnd == -1) return null;
  final attrs = text.substring(open + tag.length + 1, attrsEnd);
  if (text[attrsEnd - 1] == '/') {
    return (attrs: attrs, inner: '', next: attrsEnd + 1);
  }
  final close = text.indexOf('</$tag>', attrsEnd);
  if (close == -1) return null;
  return (
    attrs: attrs,
    inner: text.substring(attrsEnd + 1, close),
    next: close + tag.length + 3,
  );
}

String _decodeXmlEntities(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m[1]!)),
      )
      .replaceAll('&amp;', '&');
}

String _unescapeXmlText(String value) =>
    _decodeXmlEntities(value.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

/// Flatten SpreadsheetML (what MT5 writes for a Trade History Report) or the
/// PAMM/HTML2 statement markup into rows of cell text.
List<List<String>> xmlStringToRows(String text) {
  final sheet = _matchTag(text, 'Worksheet', 0);
  final table = sheet == null ? null : _matchTag(sheet.inner, 'Table', 0);
  if (table != null) {
    final rows = <List<String>>[];
    var rowPos = 0;
    while (true) {
      final row = _matchTag(table.inner, 'Row', rowPos);
      if (row == null) break;
      rowPos = row.next;
      final cells = <String>[];
      var cellPos = 0;
      var colIndex = 0;
      while (true) {
        final cell = _matchTag(row.inner, 'Cell', cellPos);
        if (cell == null) break;
        cellPos = cell.next;
        final indexMatch =
            RegExp(r'ss:Index\s*=\s*"(\d+)"').firstMatch(cell.attrs);
        final mergeDownMatch =
            RegExp(r'ss:MergeDown\s*=\s*"(\d+)"').firstMatch(cell.attrs);
        final spanMatch =
            RegExp(r'ss:MergeAcross\s*=\s*"(\d+)"').firstMatch(cell.attrs);
        final targetIndex =
            indexMatch != null ? int.parse(indexMatch[1]!) - 1 : colIndex;
        while (cells.length < targetIndex) {
          cells.add('');
        }
        final data = _matchTag(cell.inner, 'Data', 0);
        cells.add(data != null ? _unescapeXmlText(data.inner) : '');
        final colSpan =
            1 + (spanMatch != null ? int.parse(spanMatch[1]!) : 0);
        for (var extra = 1; extra < colSpan; extra++) {
          cells.add('');
        }
        colIndex = cells.length;
        if (mergeDownMatch != null && int.parse(mergeDownMatch[1]!) > 0) {
          cells.add(cells.last);
        }
      }
      rows.add(cells);
    }
    if (rows.isNotEmpty) return rows;
  }

  final rows = <List<String>>[];
  final rowRegex =
      RegExp(r'<row(?:\s[^>]*)?>([\s\S]*?)</row>', caseSensitive: false);
  final cellRegex = RegExp(
    r'<(?:[ch]:)?(?:tr|h|d|name|value)(?:\s[^>]*)?>([\s\S]*?)</(?:[ch]:)?(?:tr|h|d|name|value)>',
    caseSensitive: false,
  );
  final cellTest =
      RegExp(r'</(tr|h|d|name|value)>', caseSensitive: false);
  for (final match in rowRegex.allMatches(text)) {
    final inner = match[1] ?? '';
    if (!cellTest.hasMatch(inner)) continue;
    final cells = <String>[
      for (final cell in cellRegex.allMatches(inner))
        _unescapeXmlText(cell[1] ?? ''),
    ];
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows;
}

class ColumnMap {
  const ColumnMap({
    required this.ticket,
    required this.openDate,
    required this.openTime,
    required this.closeDate,
    required this.closeTime,
    required this.symbol,
    required this.type,
    required this.lot,
    required this.entry,
    required this.exit,
    required this.sl,
    required this.tp,
    required this.profit,
    required this.profitIsNet,
    required this.commission,
    required this.swap,
    required this.direction,
    required this.dealVolumeIdx,
  });

  final int ticket;
  final int openDate;
  final int openTime;
  final int closeDate;
  final int closeTime;
  final int symbol;
  final int type;
  final int lot;
  final int entry;
  final int exit;
  final int sl;
  final int tp;
  final int profit;
  final bool profitIsNet;
  final int commission;
  final int swap;

  /// Deals section: `Type` is buy/sell and `Direction` is in/out.
  final int direction;
  final int dealVolumeIdx;
}

ColumnMap buildColumnMap(List<String> headerRow) {
  final idx = <String, List<int>>{};
  for (var i = 0; i < headerRow.length; i++) {
    final key = normalizeHeader(headerRow[i]);
    if (key.isEmpty) continue;
    idx.putIfAbsent(key, () => <int>[]).add(i);
  }

  int first(List<String> keys) {
    for (final key in keys) {
      final hits = idx[key];
      if (hits != null && hits.isNotEmpty) return hits.first;
    }
    return -1;
  }

  int nth(String key, int n) {
    final hits = idx[key];
    return hits != null && hits.length > n ? hits[n] : -1;
  }

  final openDate = first(['date', 'opendate', 'tradedate']);
  final openTime = first(['time', 'opentime', 'starttime']);
  final closeDate = first(['closedate', 'exitdate']);
  final closeTime = first(['closetime', 'time2']) != -1
      ? first(['closetime', 'time2'])
      : nth('time', 1);
  final entry = first(['openprice', 'entryprice', 'priceopen']) != -1
      ? first(['openprice', 'entryprice', 'priceopen'])
      : nth('price', 0);
  final exit = first(['closeprice', 'exitprice', 'priceclose']) != -1
      ? first(['closeprice', 'exitprice', 'priceclose'])
      : nth('price', 1);
  final profitIsNet = [
    'netprofit',
    'netpl',
    'profitloss',
    'result',
    'gainloss',
  ].any((key) => (idx[key] ?? const []).isNotEmpty);

  return ColumnMap(
    ticket: first(['ticket', 'ticketid', 'deal', 'dealid', 'position']),
    openDate: openDate,
    openTime: openTime,
    closeDate: closeDate,
    closeTime: closeTime,
    symbol: first(['symbol', 'instrument']),
    type: first(['type', 'direction']),
    lot: first(['volume', 'lots', 'volumelots', 'size']),
    entry: entry,
    exit: exit,
    sl: first(['sl', 'stoploss']),
    tp: first(['tp', 'takeprofit']),
    profit: first([
      'profit',
      'pnl',
      'pl',
      'netprofit',
      'netpl',
      'profitloss',
      'result',
      'gainloss',
    ]),
    profitIsNet: profitIsNet,
    commission: first(['commission', 'commision', 'fee']),
    swap: first(['swap', 'swaps']),
    direction: (idx['direction'] ?? const []).isNotEmpty
        ? idx['direction']!.first
        : -1,
    dealVolumeIdx: (idx['direction'] ?? const []).isNotEmpty
        ? idx['direction']!.first + 1
        : -1,
  );
}

const Set<String> _mt5SectionMarkers = {'orders', 'deals', 'results'};

bool isMt5SectionMarker(List<String> row) {
  if (row.isEmpty) return false;
  final first = row[0].trim().toLowerCase();
  if (!_mt5SectionMarkers.contains(first)) return false;
  final rest = row
      .skip(1)
      .take(5)
      .map((cell) => cell.trim().toLowerCase())
      .where((cell) => cell.isNotEmpty && cell != 'undefined');
  return rest.isEmpty;
}

const List<String> _headerHints = [
  'date',
  'closedate',
  'exitdate',
  'time',
  'opentime',
  'closetime',
  'starttime',
  'symbol',
  'instrument',
  'type',
  'direction',
  'volume',
  'lots',
  'price',
  'openprice',
  'closeprice',
  'entryprice',
  'exitprice',
  'profit',
  'pnl',
  'pl',
  'netprofit',
  'netpl',
  'profitloss',
  'result',
  'gainloss',
  'commission',
  'swap',
  'ticket',
  'ticketid',
  'deal',
  'dealid',
  'position',
  'sl',
  'tp',
];

({int idx, ColumnMap? map}) findHeaderRow(List<List<String>> rows) {
  final limit = rows.length < 60 ? rows.length : 60;
  for (var i = 0; i < limit; i++) {
    final row = rows[i].map((cell) => cell.trim()).toList();
    if (row.length < 3) continue;
    final keys =
        row.map(normalizeHeader).where((key) => key.isNotEmpty).toSet();
    final hits = keys
        .where((key) => _headerHints.any((hint) => key.contains(hint)))
        .length;
    if (hits >= 3) return (idx: i, map: buildColumnMap(row));
  }
  return (idx: -1, map: null);
}

List<ParsedTrade> extractTrades(List<List<String>> rows) {
  final trades = <ParsedTrade>[];
  final header = findHeaderRow(rows);
  final map = header.map;

  if (header.idx != -1 && map != null) {
    String cell(List<String> row, int index) =>
        index >= 0 && index < row.length ? row[index] : '';

    String dateTime(List<String> row, int dateIndex, int timeIndex) {
      final date = cell(row, dateIndex).trim();
      final time = cell(row, timeIndex).trim();
      if (date.isNotEmpty && time.isNotEmpty && date != time) {
        return '$date $time';
      }
      return time.isNotEmpty ? time : date;
    }

    for (var i = header.idx + 1; i < rows.length; i++) {
      final row = rows[i];
      if (isMt5SectionMarker(row)) break; // next report section starts
      if (row.length < 3) continue;

      final timeVal = dateTime(row, map.openDate, map.openTime);
      if (timeVal.isEmpty || !RegExp(r'\d{4}').hasMatch(timeVal)) continue;

      final symbol = cell(row, map.symbol).trim().toUpperCase();
      final type = cell(row, map.type).trim().toUpperCase();
      final lot = parseNumeric(cell(row, map.lot));
      if (symbol.isEmpty || (type != 'BUY' && type != 'SELL') || lot <= 0) {
        continue;
      }

      // Deals-format rows: only the closing ("out") row is a trade.
      final direction = cell(row, map.direction).trim().toLowerCase();
      if (direction.isNotEmpty && direction != 'out') continue;
      final effectiveLot = direction == 'out' && map.dealVolumeIdx >= 0
          ? parseNumeric(cell(row, map.dealVolumeIdx))
          : lot;

      final profit = parseNumeric(cell(row, map.profit));
      final commission =
          normalizeSignedCost(parseNumeric(cell(row, map.commission)));
      final swap = normalizeSignedCost(parseNumeric(cell(row, map.swap)));

      trades.add(
        ParsedTrade(
          symbol: symbol,
          type: type,
          entry: parseNumeric(cell(row, map.entry)),
          exit: parseNumeric(cell(row, map.exit)),
          lot: effectiveLot,
          pnl: map.profitIsNet ? profit : profit + commission + swap,
          commission: commission,
          swap: swap,
          date: normalizeDate(timeVal),
          closeDate: normalizeDate(
            dateTime(row, map.closeDate, map.closeTime),
          ),
          sl: parseNumeric(cell(row, map.sl)),
          tp: parseNumeric(cell(row, map.tp)),
          ticket: parseTicket(cell(row, map.ticket)),
        ),
      );
    }
    return trades;
  }

  // Positional heuristics for files without a recognisable header row.
  var format = 'mt5';
  for (var i = 0; i < (rows.length < 20 ? rows.length : 20); i++) {
    final row = rows[i].map((cell) => cell.trim().toLowerCase()).toList();
    if (row.isNotEmpty &&
        row[0] == 'time' &&
        row.contains('symbol') &&
        row.contains('type')) {
      format = 'mt5';
      break;
    }
    if (row.contains('ticket') ||
        (row.length > 10 &&
            RegExp(r'[a-z]{2,6}').hasMatch(row[9]) &&
            (row[10] == 'buy' || row[10] == 'sell'))) {
      format = 'broker';
      break;
    }
  }

  var startRow = 0;
  for (var i = 0; i < (rows.length < 50 ? rows.length : 50); i++) {
    final firstCell = rows[i].isEmpty ? '' : rows[i][0].trim();
    if (RegExp(r'^\d{4}[.-]\d{2}[.-]\d{2}').hasMatch(firstCell) ||
        RegExp(r'^\d{1,2}/\d{1,2}/\d{4}').hasMatch(firstCell)) {
      startRow = i;
      break;
    }
  }

  String at(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index] : '';

  for (var i = startRow; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 8) continue;

    if (format == 'broker') {
      final time = at(row, 1).trim();
      if (time.isEmpty || !RegExp(r'\d{4}').hasMatch(time)) continue;
      final symbol = at(row, 9).trim().toUpperCase();
      final type = at(row, 10).trim().toUpperCase();
      final lot = double.tryParse(at(row, 6).trim()) ?? 0;
      if (symbol.isEmpty || (type != 'BUY' && type != 'SELL') || lot <= 0) {
        continue;
      }
      final commission = normalizeSignedCost(parseNumeric(at(row, 7)));
      final swap = normalizeSignedCost(parseNumeric(at(row, 8)));
      trades.add(
        ParsedTrade(
          symbol: symbol,
          type: type,
          entry: double.tryParse(at(row, 2).trim()) ?? 0,
          exit: double.tryParse(at(row, 4).trim()) ?? 0,
          lot: lot,
          pnl: parseNumeric(at(row, 5)) + commission + swap,
          commission: commission,
          swap: swap,
          date: normalizeDate(time),
          closeDate: normalizeDate(at(row, 3).trim()),
          sl: double.tryParse(at(row, 11).trim()) ?? 0,
          tp: double.tryParse(at(row, 12).trim()) ?? 0,
          ticket: parseTicket(at(row, 0)),
        ),
      );
    } else {
      final time = at(row, 0).trim();
      if (time.isEmpty ||
          RegExp(r'^[a-zA-Z]').hasMatch(time) ||
          !RegExp(r'\d{4}').hasMatch(time)) {
        continue;
      }
      final symbol = at(row, 2).trim().toUpperCase();
      final type = at(row, 3).trim().toUpperCase();
      final lot = double.tryParse(at(row, 4).trim()) ?? 0;
      if (symbol.isEmpty || (type != 'BUY' && type != 'SELL') || lot <= 0) {
        continue;
      }
      final commission = normalizeSignedCost(parseNumeric(at(row, 10)));
      final swap = normalizeSignedCost(parseNumeric(at(row, 11)));
      trades.add(
        ParsedTrade(
          symbol: symbol,
          type: type,
          entry: double.tryParse(at(row, 5).trim()) ?? 0,
          exit: double.tryParse(at(row, 9).trim()) ?? 0,
          lot: lot,
          pnl: parseNumeric(at(row, 12)) + commission + swap,
          commission: commission,
          swap: swap,
          date: normalizeDate(time),
          closeDate: normalizeDate(at(row, 8).trim()),
          sl: double.tryParse(at(row, 6).trim()) ?? 0,
          tp: double.tryParse(at(row, 7).trim()) ?? 0,
          // MT5 Position is not unique across partial fills, so it is not a
          // safe dedup key.
          ticket: null,
        ),
      );
    }
  }
  return trades;
}
