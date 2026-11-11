import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Answers one route: gets the decoded JSON body (or null) and the request,
/// returns the JSON response body. Throw [FakeHttpStatus] for an error.
typedef FakeRoute = FutureOr<Object?> Function(
  Object? body,
  HttpRequest request,
);

/// An HTTP error answer from a [FakeRoute].
class FakeHttpStatus implements Exception {
  const FakeHttpStatus(this.status, [this.body]);

  final int status;
  final Object? body;
}

/// A JSON REST fake on the device, for services an app reaches over HTTP
/// (a planning tool, a partner API). It runs in the test isolate, so the
/// app reaches it at `http://localhost:<port>`; point the app's base URL
/// there (Android debug builds must allow cleartext to localhost).
///
/// ```dart
/// final planner = await FakeHttp.start(port: 8091);
/// planner.post('/bookings/available-days', (body, _) => {'days': [...]});
/// planner.post(RegExp(r'^/bookings/[^/]+/book$'), (body, _) => {...});
/// ```
///
/// An unmatched request answers 404 and is logged.
class FakeHttp {
  FakeHttp._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final _routes = <(String, Pattern, FakeRoute)>[];

  /// Every request as `METHOD /path`, in order.
  final List<String> requests = [];

  int get port => _server.port;
  String get baseUrl => 'http://localhost:$port';

  static Future<FakeHttp> start({int port = 0}) async =>
      FakeHttp._(await HttpServer.bind(InternetAddress.loopbackIPv4, port));

  /// Answers [method] requests whose path matches [path]: a [String] for an
  /// exact path, a [RegExp] for a pattern.
  void on(String method, Pattern path, FakeRoute answer) =>
      _routes.add((method.toUpperCase(), path, answer));

  void get(Pattern path, FakeRoute answer) => on('GET', path, answer);
  void post(Pattern path, FakeRoute answer) => on('POST', path, answer);

  Future<void> close() => _server.close(force: true);

  bool _matches(Pattern pattern, String path) => switch (pattern) {
    final String p => p == path,
    final RegExp r => r.hasMatch(path),
    _ => false,
  };

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final line = '${request.method} $path';
    requests.add(line);
    final response = request.response..headers.contentType = ContentType.json;
    try {
      final raw = await utf8.decoder.bind(request).join();
      final body = raw.isEmpty ? null : jsonDecode(raw);
      debugPrint('jewelry: http $line ${raw.isEmpty ? '' : raw}');
      final route = _routes
          .where((r) => r.$1 == request.method && _matches(r.$2, path))
          .firstOrNull;
      if (route == null) {
        debugPrint('jewelry: no fake for http $line, answering 404');
        throw FakeHttpStatus(404, {'error': 'jewelry: no fake for $line'});
      }
      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode(await route.$3(body, request)));
    } on FakeHttpStatus catch (s) {
      response.statusCode = s.status;
      response.write(jsonEncode(s.body));
    } catch (e) {
      debugPrint('jewelry: fake for http $line threw: $e');
      response.statusCode = HttpStatus.internalServerError;
      response.write(jsonEncode({'error': '$e'}));
    }
    await response.close();
  }
}
