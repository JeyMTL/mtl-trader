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
    Duration timeout = const Duration(seconds: 25),
  })  : _client = client,
        _accessToken = accessToken ?? _noToken,
        _timeout = timeout;

  final HttpClient? _client;
  final String? Function() _accessToken;
  final Duration _timeout;

  static String? _noToken() => null;

  Future<ApiResponse> send(
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
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
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
    final token = _token();
    final boundary = 'mtl${DateTime.now().microsecondsSinceEpoch}';
    final client = _client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 10));
    try {
      final request = await client.postUrl(
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
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
