import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/config.dart';

/// A failed call to the web API, already translated into a sentence a trader
/// can act on. [code] carries the server's machine-readable reason (for example
/// `upgrade_required`), so a caller can render a plan prompt instead of an
/// error without parsing the message.
class ApiTransportException implements Exception {
  ApiTransportException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

/// A decoded, already status-checked response.
class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}

/// JSON and multipart calls to the web API.
///
/// Two clients used to carry their own copy of bearer-token handling, JSON
/// decoding and error wording; a change to any of them had to be made twice.
/// This is now the only place that opens a request.
class ApiTransport {
  ApiTransport({
    HttpClient? client,
    String? Function()? accessToken,
    Future<void> Function()? refreshSession,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 25),
  })  : _client = client,
        _accessToken = accessToken ?? _noToken,
        _refreshSessionCallback = refreshSession,
        _baseUrl = baseUrl,
        _timeout = timeout;

  final HttpClient? _client;
  final String? Function() _accessToken;
  final Future<void> Function()? _refreshSessionCallback;
  /// Only a test overrides this; every real call goes to the build's API.
  final String? _baseUrl;
  final Duration _timeout;

  String get _origin => _baseUrl ?? AppConfig.apiBaseUrl;

  static String? _noToken() => null;

  /// How long to wait before the one retry a dropped connection earns.
  static const Duration _retryDelay = Duration(milliseconds: 300);

  /// A request, retried once when the connection itself failed.
  ///
  /// Each call opens its own client, so a phone handed an address it cannot
  /// reach — carriers here are known to blackhole single Vercel anycast
  /// addresses — loses the whole call on the first try. A second attempt
  /// resolves the name again and usually lands on a working address, which
  /// turns a dead request into a slow one. Timeouts and HTTP errors are
  /// answers, not drops, so they are not retried.
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
    String? fallbackError,
  }) async {
    Future<ApiResponse> attempt() => _withNetworkRetry(
          () => _sendOnce(
            method,
            path,
            body: body,
            timeout: timeout,
            fallbackError: fallbackError,
          ),
        );

    try {
      return await attempt();
    } on ApiTransportException catch (error) {
      // A 401 is what a token that expired while the phone slept looks like.
      // Refresh once and send it again before telling the trader to sign in.
      if (error.statusCode != 401 || !await _refreshSession()) rethrow;
      return attempt();
    }
  }

  /// Runs [send], retrying once when the connection itself failed.
  Future<ApiResponse> _withNetworkRetry(
    Future<ApiResponse> Function() send,
  ) async {
    try {
      return await send();
    } on ApiTransportException catch (error) {
      if (error.code != 'network') rethrow;
      await Future<void>.delayed(_retryDelay);
      return send();
    }
  }

  /// Rotates the session once after a 401. False when there is nothing to
  /// refresh or the refresh itself failed, so the 401 stands as the answer.
  Future<bool> _refreshSession() async {
    final refresh = _refreshSessionCallback;
    if (refresh == null) return false;
    try {
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ApiResponse> _sendOnce(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
    String? fallbackError,
  }) async {
    final token = _token();
    final client = _client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 10));
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('$_origin$path'),
      );
      _authorize(request, token);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(timeout ?? _timeout);
      final text = await response.transform(utf8.decoder).join();
      return _decode(response.statusCode, text, fallbackError);
    } on ApiTransportException {
      rethrow;
    } on TimeoutException {
      throw ApiTransportException(
        'The server took too long to answer. Try again.',
        code: 'timeout',
      );
    } catch (_) {
      throw ApiTransportException(
        'Could not reach the server. Check your connection and try again.',
        code: 'network',
      );
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  /// A `multipart/form-data` upload with one file field. Used for statement
  /// formats the device cannot decode itself; the bytes never touch storage.
  Future<ApiResponse> upload(
    String path, {
    required String fileName,
    required Uint8List bytes,
    String field = 'file',
    Duration? timeout,
    String? fallbackError,
  }) async {
    try {
      return await _uploadOnce(
        path,
        fileName: fileName,
        bytes: bytes,
        field: field,
        timeout: timeout,
        fallbackError: fallbackError,
      );
    } on ApiTransportException catch (error) {
      if (error.statusCode != 401 || !await _refreshSession()) rethrow;
      return _uploadOnce(
        path,
        fileName: fileName,
        bytes: bytes,
        field: field,
        timeout: timeout,
        fallbackError: fallbackError,
      );
    }
  }

  Future<ApiResponse> _uploadOnce(
    String path, {
    required String fileName,
    required Uint8List bytes,
    required String field,
    Duration? timeout,
    String? fallbackError,
  }) async {
    final token = _token();
    final boundary = 'mtl${DateTime.now().microsecondsSinceEpoch}';
    final client = _client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 10));
    try {
      final request = await client.postUrl(
        Uri.parse('$_origin$path'),
      );
      _authorize(request, token);
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );

      // Quotes and newlines in a file name would break the part header.
      final safeName = fileName.replaceAll(RegExp(r'["\r\n]'), ' ');
      request.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$field"; filename="$safeName"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
      );
      request.add(bytes);
      request.add(utf8.encode('\r\n--$boundary--\r\n'));

      final response = await request.close().timeout(timeout ?? _timeout);
      final text = await response.transform(utf8.decoder).join();
      return _decode(response.statusCode, text, fallbackError);
    } on ApiTransportException {
      rethrow;
    } on TimeoutException {
      throw ApiTransportException(
        'The server took too long to answer. Try again.',
        code: 'timeout',
      );
    } catch (_) {
      throw ApiTransportException(
        'Could not reach the server. Check your connection and try again.',
        code: 'network',
      );
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  String _token() {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw ApiTransportException(
        'Your session expired. Sign in again.',
        code: 'unauthorized',
        statusCode: 401,
      );
    }
    return token;
  }

  void _authorize(HttpClientRequest request, String token) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }

  ApiResponse _decode(int statusCode, String text, String? fallbackError) {
    dynamic decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    final body =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

    if (statusCode >= 400) {
      final message = body['error'];
      throw ApiTransportException(
        message is String && message.trim().isNotEmpty
            ? message
            : fallbackError ?? 'Request failed ($statusCode). Try again.',
        code: body['code']?.toString(),
        statusCode: statusCode,
      );
    }
    return ApiResponse(statusCode, body);
  }
}
