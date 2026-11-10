import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Answers one callable: gets the request `data`, returns the `result`.
/// Throw a [FunctionsFailure] to answer with a callable error.
typedef FakeCallable = FutureOr<Object?> Function(Object? data);

/// A callable error, as `FirebaseFunctionsException` sees it in the app:
/// [status] is the code (`NOT_FOUND`, `INVALID_ARGUMENT`, `UNAVAILABLE`, ...).
class FunctionsFailure implements Exception {
  const FunctionsFailure(this.status, [this.message = '', this.details]);

  final String status;
  final String message;
  final Object? details;

  @override
  String toString() => 'FunctionsFailure($status: $message)';
}

/// One call the app made.
class FunctionsCall {
  const FunctionsCall(this.name, this.data);

  final String name;
  final Object? data;

  @override
  String toString() => '$name(${jsonEncode(data)})';
}

/// Fake Cloud Functions for scenarios: a callable endpoint on the Functions
/// emulator port that answers with Dart closures.
///
/// The app points its `FirebaseFunctions` at the emulator as usual
/// ([FirebaseEmulator.useIfRequested]); this server takes the place of the
/// Functions emulator. It runs in the test isolate, on the device. On
/// Android the jewelry CLI forwards the host port to it, so `10.0.2.2:5001`
/// reaches it from every app isolate; the iOS simulator shares localhost.
///
/// ```dart
/// final functions = await ctx.fakeFunctions();
/// functions.on('userBsnCheck', (data) => {'isValid': true});
/// functions.fail('relayCallToKadaster', 'UNAVAILABLE');
/// ...
/// expect(functions.callsTo('userBsnCheck'), hasLength(1));
/// ```
///
/// A callable without a fake answers `NOT_FOUND` and is logged, so a
/// missing mock shows up in the output instead of hanging.
class FakeFunctions {
  FakeFunctions._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final _fakes = <String, FakeCallable>{};

  /// Every call in order, answered or not.
  final List<FunctionsCall> calls = [];

  int get port => _server.port;

  /// Starts listening on [port] (the Functions emulator port).
  static Future<FakeFunctions> start({int port = 5001}) async =>
      FakeFunctions._(await HttpServer.bind(InternetAddress.anyIPv4, port));

  /// Answers [name] with [answer]. [name] is the callable name as the app
  /// calls it, for example `Notificare-callableGetUserBasedInbox`.
  void on(String name, FakeCallable answer) => _fakes[name] = answer;

  /// Answers [name] with a fixed [result].
  void returns(String name, Object? result) => on(name, (_) => result);

  /// Answers [name] with a callable error.
  void fail(String name, String status, [String message = '']) =>
      on(name, (_) => throw FunctionsFailure(status, message));

  List<FunctionsCall> callsTo(String name) =>
      [for (final c in calls) if (c.name == name) c];

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    // Path: /<project>/<region>/<name>
    final name = request.uri.pathSegments.isEmpty
        ? ''
        : request.uri.pathSegments.last;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = body.isEmpty ? null : (jsonDecode(body) as Map)['data'];
      final call = FunctionsCall(name, data);
      calls.add(call);
      debugPrint('jewelry: callable $call');
      final fake = _fakes[name];
      if (fake == null) {
        debugPrint(
          'jewelry: no fake for callable "$name", answering NOT_FOUND '
          '(fakes: ${_fakes.keys.join(', ')})',
        );
        throw FunctionsFailure('NOT_FOUND', 'jewelry: no fake for "$name"');
      }
      final result = await fake(data);
      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode({'result': result}));
    } on FunctionsFailure catch (f) {
      response.statusCode = _httpStatus(f.status);
      response.write(jsonEncode({
        'error': {
          'status': f.status,
          'message': f.message,
          if (f.details != null) 'details': f.details,
        },
      }));
    } catch (e) {
      debugPrint('jewelry: fake for callable "$name" threw: $e');
      response.statusCode = HttpStatus.internalServerError;
      response.write(jsonEncode({
        'error': {'status': 'INTERNAL', 'message': '$e'},
      }));
    }
    await response.close();
  }

  // https://firebase.google.com/docs/functions/callable-reference
  static int _httpStatus(String status) => switch (status) {
    'INVALID_ARGUMENT' || 'FAILED_PRECONDITION' || 'OUT_OF_RANGE' => 400,
    'UNAUTHENTICATED' => 401,
    'PERMISSION_DENIED' => 403,
    'NOT_FOUND' => 404,
    'ALREADY_EXISTS' || 'ABORTED' => 409,
    'RESOURCE_EXHAUSTED' => 429,
    'CANCELLED' => 499,
    'UNIMPLEMENTED' => 501,
    'UNAVAILABLE' => 503,
    'DEADLINE_EXCEEDED' => 504,
    _ => 500,
  };
}
