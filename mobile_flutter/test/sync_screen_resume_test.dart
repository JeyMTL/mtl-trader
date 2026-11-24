import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/models/models.dart';
import 'package:mtl_trader_mobile/screens/sync_screen.dart';
import 'package:mtl_trader_mobile/services/journal_api.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

/// Stands in for the network and counts how often the screen asks for the
/// connection, which is the whole point: a screen that has given up polling must
/// ask again when the app comes back.
class _CountingApi implements JournalApi {
  _CountingApi(this.status);

  String status;
  int connectionCalls = 0;

  @override
  Future<Map<String, dynamic>> brokerConnection() async {
    connectionCalls += 1;
    return {'status': status};
  }

  @override
  Future<List<Mt5Broker>> brokers() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _harness(Widget home) => MaterialApp(
      theme: buildFlatTheme(AppPalette.dark),
      home: home,
    );

void main() {
  testWidgets('coming back to the foreground re-reads the connection',
      (tester) async {
    final api = _CountingApi('connecting');
    await tester.pumpWidget(_harness(SyncScreen(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.connectionCalls, 1);
    expect(find.text('CONNECTING…'), findsOneWidget);

    // The session came up while the phone was in a pocket.
    api.status = 'connected';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.connectionCalls, 2);
    expect(find.text('CONNECTED'), findsOneWidget);
    expect(api.status, 'connected');

    // Dispose the screen so its poll timer does not outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a resumed screen gets its full polling window back',
      (tester) async {
    final api = _CountingApi('connecting');
    await tester.pumpWidget(_harness(SyncScreen(api: api)));
    await tester.pump();

    // Let the two-minute cutoff fire, which stops the poll.
    await tester.pump(const Duration(minutes: 2, seconds: 1));
    final afterStall = api.connectionCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.connectionCalls, afterStall + 1);

    // And it is polling again, not just one extra read: six seconds later.
    await tester.pump(const Duration(seconds: 6));
    expect(api.connectionCalls, afterStall + 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
