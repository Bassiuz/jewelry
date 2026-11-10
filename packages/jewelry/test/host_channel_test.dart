import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/host_channel.dart';

void main() {
  test('request is answered by id and errors become exceptions', () async {
    final channel = await HostChannel.open('test');
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      HostChannel.port,
    );
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final req = jsonDecode(line) as Map<String, dynamic>;
          final ok = req['action'] == 'screenshot';
          client.writeln(
            jsonEncode({
              'id': req['id'],
              'ok': ok,
              if (ok) 'result': 'bytes-for-${req['args']['label']}',
              if (!ok) 'error': 'nope',
            }),
          );
        });

    expect(await channel.request('screenshot', {'label': 'a'}), 'bytes-for-a');
    await expectLater(channel.request('background'), throwsStateError);
    await client.close();
    await channel.close();
  });
}
