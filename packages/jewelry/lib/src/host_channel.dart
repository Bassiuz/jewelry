import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'scenario_recording.dart';

/// Device side of the host channel. The on-device test listens on a fixed
/// port and prints a marker; the CLI forwards the port (adb) or connects
/// directly (simulator) and answers requests with adb or simctl.
///
/// Wire format: one JSON object per line. Request `{"id", "action", "args"}`,
/// response `{"id", "ok", "result"?, "error"?}`.
class HostChannel {
  HostChannel._(this._server);

  static const port = 47831;
  final ServerSocket _server;
  Socket? _socket;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;

  static Future<HostChannel> open(String scenario) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    // ignore: avoid_print
    print(
      '${ScenarioRecording.channelMarker}\t$port\t'
      '${Directory.systemTemp.path}\t$scenario',
    );
    return HostChannel._(server);
  }

  Future<Socket> _connection() async {
    if (_socket != null) return _socket!;
    final socket = await _server.first;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final msg = jsonDecode(line) as Map<String, dynamic>;
          _pending.remove(msg['id'] as int)?.complete(msg);
        });
    return _socket = socket;
  }

  Future<Object?> request(
    String action, [
    Map<String, Object?> args = const {},
  ]) async {
    final socket = await _connection();
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    socket.writeln(jsonEncode({'id': id, 'action': action, 'args': args}));
    final response = await completer.future;
    if (response['ok'] != true) {
      throw StateError('Host action $action failed: ${response['error']}');
    }
    return response['result'];
  }

  Future<void> close() async {
    await _socket?.close();
    await _server.close();
  }
}
