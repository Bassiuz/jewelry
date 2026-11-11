import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';
import 'package:jewelry/src/dashboard.dart';
import 'package:jewelry/src/run_log.dart';
import 'package:jewelry/src/scenario_result.dart';

import 'test_png.dart';

void main() {
  test('the dashboard follows a run and serves it', () async {
    final d = Dashboard(root: Directory.systemTemp);
    await d.start(port: 0);
    addTearDown(d.stop);
    d
      ..queue('pixel', ['a_test.dart', 'b_test.dart'])
      ..started('pixel', 'a_test.dart', 0)
      ..planned('pixel', 0, 'Diary note', ['Log in', 'Write', 'Saved'])
      ..step('pixel', 0, 'Write');

    Future<String> get(String path) async {
      final r = await (await HttpClient().getUrl(d.url.resolve(path))).close();
      return utf8.decode(await r.expand((b) => b).toList());
    }

    var state = jsonDecode(await get('state.json')) as Map;
    final a = (state['tests'] as List).first as Map;
    expect(a['state'], 'running');
    expect(a['labels'], ['Diary note']);
    final w = (state['workers'] as List).single as Map;
    expect(w['steps'], ['Log in', 'Write', 'Saved']);
    expect(w['step'], 'Write');

    d
      ..judging('pixel', 0)
      ..finished('pixel', 'a_test.dart', [
        ScenarioResult(
          label: 'Diary note',
          file: 'a_test.dart',
          profile: 'pixel',
          outcome: Outcome.failed,
          duration: const Duration(seconds: 40),
          ranAt: DateTime(2026, 11, 11),
          reason: 'Step "Write" failed',
          frames: 10,
        ),
      ]);
    state = jsonDecode(await get('state.json')) as Map;
    expect(((state['tests'] as List).first as Map)['state'], 'failed');
    expect(((state['tests'] as List).last as Map)['state'], 'queued');
    expect(await get(''), contains('<title>jewelry</title>'));

    d.failed('pixel', 3, StateError('Firebase emulator ports are taken'));
    state = jsonDecode(await get('state.json')) as Map;
    final w4 = (state['workers'] as List).firstWhere((w) => w['worker'] == 3) as Map;
    expect(w4['error'], 'Firebase emulator ports are taken');
  });

  test('the accept button makes the run of a failure its golden', () async {
    final root = Directory.systemTemp.createTempSync('jewelry_accept');
    addTearDown(() => root.deleteSync(recursive: true));
    final r = ScenarioResult(
      label: 'Diary note',
      file: 'a_test.dart',
      profile: 'pixel',
      outcome: Outcome.failed,
      duration: const Duration(seconds: 40),
      ranAt: DateTime(2026, 11, 11),
      acceptable: true,
    );
    final failure = Directory('${root.path}/${r.failureDir}')..createSync(recursive: true);
    ScenarioRecording([pixel(1, 2, 3)]).write('${failure.path}/actual');
    final d = Dashboard(root: root)..showLog(RunLog(root, [r]));
    await d.start(port: 0);
    addTearDown(d.stop);

    final req = await HttpClient().postUrl(d.url.resolve('accept/${Uri.encodeComponent('pixel|a_test.dart')}'));
    final body = jsonDecode(utf8.decode(await (await req.close()).expand((b) => b).toList()));
    expect(body['accepted'], 1);
    expect(File('${root.path}/${r.goldenBase}.apng').existsSync(), isTrue);
    expect(failure.existsSync(), isFalse);
    expect(((d.state['tests'] as List).single as Map)['state'], 'accepted');
  });
}
