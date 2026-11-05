import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/import_parser.dart';

const String _mt5Csv = '''
Time,Position,Symbol,Type,Volume,Price,S / L,T / P,Time,Price,Commission,Swap,Profit
2026.10.01 09:30:00,12345,EURUSD,buy,0.50,1.10000,1.09000,1.12000,2026.10.01 11:00:00,1.11000,-2.00,-1.00,100.00
Orders
2026.10.01 09:30:00,555,EURUSD,buy,0.50,1.10000,0.00000,0.00000,2026.10.01 11:00:00,1.11000,0.00,0.00,100.00
''';

void main() {
  test('reads an MT5 positions export and ignores the Orders section', () {
    final rows = parseFileRows('history.csv', Uint8List.fromList(utf8.encode(_mt5Csv)));
    final trades = extractTrades(rows);

    expect(trades, hasLength(1));
    final trade = trades.single;
    expect(trade.symbol, 'EURUSD');
    expect(trade.type, 'BUY');
    expect(trade.lot, 0.5);
    expect(trade.entry, 1.1);
    expect(trade.exit, 1.11);
    expect(trade.ticket, 12345);
    expect(trade.date, '2026-10-01T09:30:00');
    expect(trade.closeDate, '2026-10-01T11:00:00');
    // Profit plus signed commission and swap, the same net figure the web desk
    // stores.
    expect(trade.pnl, 97);
    expect(trade.commission, -2);
    expect(trade.swap, -1);
  });

  test('sniffs semicolons and European number formatting', () {
    const text = 'Date;Symbol;Type;Volume;Open Price;Close Price;Profit\n'
        '2026-10-02 08:00:00;GBPUSD;sell;1,50;1,27000;1,26000;1.234,56\n';

    expect(detectDelimiter(text), ';');
    final trades = extractTrades(
      parseFileRows('broker.csv', Uint8List.fromList(utf8.encode(text))),
    );

    expect(trades, hasLength(1));
    expect(trades.single.type, 'SELL');
    expect(trades.single.lot, 1.5);
    expect(trades.single.pnl, 1234.56);
  });

  test('reads the XML report MT5 writes for the history', () {
    const xml = '''<?xml version="1.0"?>
<Workbook xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
 <Worksheet ss:Name="Report">
  <Table>
   <Row>
    <Cell><Data ss:Type="String">Time</Data></Cell>
    <Cell><Data ss:Type="String">Symbol</Data></Cell>
    <Cell><Data ss:Type="String">Type</Data></Cell>
    <Cell><Data ss:Type="String">Volume</Data></Cell>
    <Cell><Data ss:Type="String">Profit</Data></Cell>
   </Row>
   <Row>
    <Cell><Data ss:Type="String">2026.10.03 14:05:00</Data></Cell>
    <Cell><Data ss:Type="String">USDJPY</Data></Cell>
    <Cell><Data ss:Type="String">sell</Data></Cell>
    <Cell><Data ss:Type="Number">0.25</Data></Cell>
    <Cell><Data ss:Type="Number">12.5</Data></Cell>
   </Row>
  </Table>
 </Worksheet>
</Workbook>''';

    final rows = parseFileRows(
      'ReportHistory-1234567.xml',
      Uint8List.fromList(utf8.encode(xml)),
    );
    final trades = extractTrades(rows);

    expect(trades, hasLength(1));
    expect(trades.single.symbol, 'USDJPY');
    expect(trades.single.type, 'SELL');
    expect(trades.single.pnl, 12.5);
    expect(trades.single.date, '2026-10-03T14:05:00');
  });

  test('reads an Excel .xlsx export', () {
    final bytes = File('test/fixtures/history.xlsx').readAsBytesSync();
    final trades = extractTrades(parseFileRows('history.xlsx', bytes));

    expect(trades, hasLength(1));
    expect(trades.single.symbol, 'XAUUSD');
    expect(trades.single.lot, 0.1);
    expect(trades.single.ticket, 777);
    expect(trades.single.date, '2026-10-05T10:00:00');
    expect(trades.single.closeDate, '2026-10-05T12:00:00');
    // 100 profit less the 1.50 commission.
    expect(trades.single.pnl, 98.5);
  });

  test('normalises the number and date shapes broker exports use', () {
    expect(parseNumeric(r'$1,234.56'), 1234.56);
    expect(parseNumeric('(12.50)'), -12.5);
    expect(normalizeSignedCost(3), -3);
    expect(normalizeSignedCost(-3), -3);
    expect(normalizeDate('10/04/2026 09:30:00'), '2026-10-04T09:30:00');
    // An open position has no close time, so it is not a closed trade.
    expect(normalizeDate('Currently Running'), '');
    expect(parseTicket('Ticket #98765'), 98765);
    expect(parseTicket('n/a'), isNull);
  });
}
