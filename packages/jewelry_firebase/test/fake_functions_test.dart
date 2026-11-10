import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry_firebase/jewelry_firebase.dart';

/// Calls [name] the way the Firebase SDK does: POST {"data": ...}.
Future<(int, Map<String, dynamic>)> call(FakeFunctions f, String name, Object? data) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${f.port}/my-app-dev/europe-west3/$name'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'data': data}));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (response.statusCode, jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close();
  }
}

void main() {
  late FakeFunctions functions;
  setUp(() async => functions = await FakeFunctions.start(port: 0));
  tearDown(() => functions.close());

  test('a fake answers with its result and the call is recorded', () async {
    functions.on('userBsnCheck', (data) => {'isValid': (data as Map)['bsn'] == '123456782'});
    final (status, body) = await call(functions, 'userBsnCheck', {'bsn': '123456782'});
    expect(status, 200);
    expect(body, {'result': {'isValid': true}});
    expect(functions.callsTo('userBsnCheck').single.data, {'bsn': '123456782'});
  });

  test('fail answers with a callable error and its HTTP status', () async {
    functions.fail('relayCallToKadaster', 'UNAVAILABLE', 'Kadaster is down');
    final (status, body) = await call(functions, 'relayCallToKadaster', {});
    expect(status, 503);
    expect(body['error'], {'status': 'UNAVAILABLE', 'message': 'Kadaster is down'});
  });

  test('a callable without a fake answers NOT_FOUND', () async {
    final (status, body) = await call(functions, 'calculateGrossMargin', null);
    expect(status, 404);
    expect((body['error'] as Map)['status'], 'NOT_FOUND');
    expect(functions.calls.single.name, 'calculateGrossMargin');
  });

  test('a fake that throws answers INTERNAL', () async {
    functions.on('getPickupPoint', (_) => throw StateError('bad mock'));
    final (status, body) = await call(functions, 'getPickupPoint', null);
    expect(status, 500);
    expect((body['error'] as Map)['status'], 'INTERNAL');
  });
}
