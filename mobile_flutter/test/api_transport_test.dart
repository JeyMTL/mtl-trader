import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/services/api_transport.dart';

/// Answers every request with 401 until the bearer token is [fresh], whose
/// value is set by `refreshSession`. Records what each request carried.
class _Server {
  _Server(this._server);

  final HttpServer _server;
  final List<String> authorization = <String>[];
  String fresh = 'fresh';

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_Server> start() async {
    final socket = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _Server(socket);
    socket.listen((request) async {
      final header =
          request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      server.authorization.add(header);
      final accepted = header == 'Bearer ${server.fresh}';
      request.response.statusCode = accepted ? 200 : 401;
      request.response.write(
        accepted ? '{"ok":true}' : '{"error":"Unauthorized"}',
      );
      await request.response.close();
    });
    return server;
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  test('a 401 refreshes the session once and resends the call', () async {
    final server = await _Server.start();
    addTearDown(server.close);

    var token = 'expired';
    var refreshes = 0;
    final transport = ApiTransport(
      baseUrl: server.baseUrl,
      accessToken: () => token,
      refreshSession: () async {
        refreshes += 1;
        token = 'fresh';
      },
    );

    final response = await transport.send('GET', '/api/broker/connection');

    expect(response.statusCode, 200);
    expect(refreshes, 1);
    expect(server.authorization, ['Bearer expired', 'Bearer fresh']);
  });

  test('a 401 stays an error when the refresh fails', () async {
    final server = await _Server.start();
    addTearDown(server.close);

    var refreshes = 0;
    final transport = ApiTransport(
      baseUrl: server.baseUrl,
      accessToken: () => 'expired',
      refreshSession: () async {
        refreshes += 1;
        throw StateError('refresh rejected');
      },
    );

    await expectLater(
      transport.send('GET', '/api/sync?userId=u1'),
      throwsA(
        isA<ApiTransportException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', 'Unauthorized'),
      ),
    );
    expect(refreshes, 1);
    // One attempt: a refresh that failed earns no second request.
    expect(server.authorization, ['Bearer expired']);
  });

  test('no session at all never reaches the network', () async {
    final transport = ApiTransport(
      baseUrl: 'http://127.0.0.1:1',
      accessToken: () => null,
      refreshSession: () async {},
    );

    await expectLater(
      transport.send('GET', '/api/broker/connection'),
      throwsA(
        isA<ApiTransportException>().having(
          (error) => error.message,
          'message',
          'Your session expired. Sign in again.',
        ),
      ),
    );
  });
}
