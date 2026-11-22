import 'package:flutter_test/flutter_test.dart';

import 'package:mtl_trader_mobile/core/friendly_error.dart';

void main() {
  test('hides PostgREST and Play exception wrappers', () {
    expect(
      friendlyError(
        Exception(
          'PostgrestException(message: permission denied for table trades, '
          'code: 42501, details: null, hint: null)',
        ),
        fallback: 'Could not save your trade.',
      ),
      'Could not save your trade.',
    );
    expect(
      friendlyError(
        'PlatformException(BillingClient: Service disconnected, null, null)',
        fallback: 'Could not reach Google Play.',
      ),
      'Could not reach Google Play.',
    );
    expect(
      friendlyError('Supabase is unreachable', fallback: 'No data.'),
      'No data.',
    );
  });

  test('turns a socket failure into a connection sentence', () {
    expect(
      friendlyError('SocketException: Failed host lookup: mtlledger.com'),
      'Could not reach the server. Check your connection and try again.',
    );
  });

  test('keeps a message the app wrote itself', () {
    expect(
      friendlyError(Exception('Daily loss limit reached.')),
      'Daily loss limit reached.',
    );
  });

  test('falls back for empty, missing and JSON-shaped errors', () {
    expect(friendlyError(null), 'Something went wrong. Please try again.');
    expect(friendlyError(''), 'Something went wrong. Please try again.');
    expect(friendlyError('{"code":"PGRST301"}'),
        'Something went wrong. Please try again.');
  });

  test('names a throttle instead of repeating it', () {
    expect(
      friendlyError('Too many requests'),
      'Too many attempts. Please wait a moment and try again.',
    );
  });
}
