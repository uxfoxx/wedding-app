import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the API lives. Override with --dart-define=API_URL=https://api.example.lk
/// The web panel is served by the API itself, so it defaults to the page's own origin.
String apiBaseUrl() {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb) return Uri.base.origin;
  // Android emulator reaches the host machine on 10.0.2.2; iOS simulator on localhost.
  return defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
}

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.extra = const {}]);
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> extra;

  /// 402 = the free plan doesn't include this; show the upgrade screen.
  bool get needsUpgrade => status == 402;

  @override
  String toString() => message;
}

class Api {
  Api({String? baseUrl, http.Client? client})
      : base = baseUrl ?? apiBaseUrl(),
        _http = client ?? http.Client();

  final String base;
  final http.Client _http;
  String? token;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$base/api$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) => _send('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});
  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> put(String path, Object body) => _send('PUT', path, body: body);
  Future<Map<String, dynamic>> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final req = http.Request(method, _uri(path, query));
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    } catch (_) {
      throw ApiException(0, 'offline', 'Could not reach the server. Check your connection and try again.');
    }
    final text = utf8.decode(res.bodyBytes);
    final Map<String, dynamic> json = text.isEmpty
        ? {}
        : (() {
            try {
              final v = jsonDecode(text);
              return v is Map<String, dynamic> ? v : {'data': v};
            } catch (_) {
              return {'raw': text};
            }
          })();
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, json['error']?.toString() ?? 'error', json['message']?.toString() ?? 'Something went wrong.', json);
    }
    return json;
  }

  /// Raw text download (CSV export).
  Future<String> getText(String path) async {
    final res = await _http.get(_uri(path), headers: {if (token != null) 'authorization': 'Bearer $token'});
    if (res.statusCode >= 400) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      throw ApiException(res.statusCode, j['error'] ?? 'error', j['message'] ?? 'Something went wrong.', j);
    }
    return utf8.decode(res.bodyBytes);
  }
}
