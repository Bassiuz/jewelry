import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/captured_frame.dart';
import 'package:jewelry/src/scenario_recording.dart';
import 'package:jewelry/src/video.dart';

import 'test_png.dart';

void main() {
  test('phone frames show longer than app frames', () {
    final app = pixel(1, 2, 3);
    expect(videoDuration(app), const Duration(microseconds: 16667));
    final phone = CapturedFrame(step: 's', png: app.png, device: true);
    expect(videoDuration(phone), const Duration(milliseconds: 100));
  });

  test(
    'a recording becomes an MP4',
    () async {
      final out = File('${Directory.systemTemp.path}/jewelry_video_test.mp4');
      await writeVideo(
        ScenarioRecording([
          for (var i = 0; i < 30; i++) pixel(255, 0, 0),
          pixel(0, 255, 0),
        ]),
        out,
      );
      expect(out.lengthSync(), greaterThan(0));
    },
    skip: Process.runSync('which', ['ffmpeg']).exitCode != 0 ? 'no ffmpeg' : false,
  );

  test('the timeline puts each step where the video shows it', () {
    final tl = videoTimeline(
      '[{"step":"a","frames":60},{"step":"b","frames":10,"device":true},'
      '{"step":"b","frames":1,"snapshot":"Home"}]',
    );
    expect(tl.map((r) => r['kind']), ['app', 'device', 'app']);
    expect(tl[1]['start'], closeTo(1.0, 0.001));
    expect(tl[1]['end'], closeTo(2.0, 0.001));
    expect(tl[2]['snapshot'], 'Home');
  });
}
