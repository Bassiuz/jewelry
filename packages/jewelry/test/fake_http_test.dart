import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

Future<(int, Object?)> post(FakeHttp f, String path, Object body) async {
  final client = HttpClient();
  try {
    final r = await client.postUrl(Uri.parse('${f.baseUrl}$path'));
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode(body));
    final response = await r.close();
    return (response.statusCode, jsonDecode(await utf8.decoder.bind(response).join()));
  } finally {
    client.close();
  }
}

void main() {
  late FakeHttp http;
  setUp(() async => http = await FakeHttp.start());
  tearDown(() => http.close());

  test('an exact route answers with its JSON', () async {
    http.post('/bookings/available-days', (body, _) => {'days': ['2026-01-07'], 'week': (body! as Map)['week']});
    final (status, body) = await post(http, '/bookings/available-days', {'week': 2});
    expect(status, 200);
    expect(body, {'days': ['2026-01-07'], 'week': 2});
    expect(http.requests, ['POST /bookings/available-days']);
  });

  test('a pattern route matches a path with an id', () async {
    http.post(RegExp(r'^/bookings/[^/]+/book$'), (_, r) => {'path': r.uri.path});
    expect((await post(http, '/bookings/slot-1/book', {})).$2, {'path': '/bookings/slot-1/book'});
  });

  test('an unmatched request is a 404, a FakeHttpStatus its own status', () async {
    http.post('/x', (_, _) => throw const FakeHttpStatus(409, {'error': 'taken'}));
    expect((await post(http, '/nowhere', {})).$1, 404);
    final (status, body) = await post(http, '/x', {});
    expect(status, 409);
    expect(body, {'error': 'taken'});
  });
}
