import 'dart:io';

import 'captured_frame.dart';
import 'scenario_recording.dart';

/// How long one frame shows in a shared video. App frames play at their
/// recorded 60 Hz; phone frames (lock screen, home screen) were taken about
/// once a second while the scenario waited, and show for a tenth of one,
/// so a minute of waiting plays in a few seconds without flashing by.
Duration videoDuration(CapturedFrame f) => f.device
    ? const Duration(milliseconds: 100)
    : const Duration(microseconds: 16667);

/// Writes [recording] as an H.264 MP4 at [out] through `ffmpeg`: small
/// enough for Slack, and plays anywhere, unlike an APNG.
Future<void> writeVideo(ScenarioRecording recording, File out) async {
  final tmp = await Directory.systemTemp.createTemp('jewelry_video');
  try {
    // Runs of identical frames become one image shown for their summed
    // time: pauses and settles are most of a recording.
    final list = StringBuffer();
    var n = 0;
    CapturedFrame? last;
    var shown = Duration.zero;
    void flush() {
      if (last == null) return;
      final name = 'f${(n++).toString().padLeft(5, '0')}.png';
      File('${tmp.path}/$name').writeAsBytesSync(last.png);
      list
        ..writeln("file '$name'")
        ..writeln('duration ${shown.inMicroseconds / 1e6}');
    }

    for (final f in recording.frames) {
      if (last != null && last.device == f.device && _same(last.png, f.png)) {
        shown += videoDuration(f);
        continue;
      }
      flush();
      last = f;
      shown = videoDuration(f);
    }
    flush();
    // The concat demuxer drops the last entry's duration unless the file
    // is listed once more.
    if (n > 0) {
      list.writeln("file 'f${(n - 1).toString().padLeft(5, '0')}.png'");
    }
    File('${tmp.path}/list.txt').writeAsStringSync(list.toString());

    out.parent.createSync(recursive: true);
    final r = await Process.run('ffmpeg', [
      '-v', 'error', '-y',
      '-f', 'concat', '-safe', '0', '-i', '${tmp.path}/list.txt',
      // H.264 needs even sizes; 30 fps is plenty to watch.
      '-vf', 'fps=30,pad=ceil(iw/2)*2:ceil(ih/2)*2',
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '26',
      '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
      out.path,
    ]);
    if (r.exitCode != 0) {
      throw ProcessException('ffmpeg', const [], '${r.stderr}', r.exitCode);
    }
  } on ProcessException catch (e) {
    if (e.errorCode == 2 || '$e'.contains('No such file')) {
      throw StateError('jewelry video needs ffmpeg: brew install ffmpeg');
    }
    rethrow;
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

bool _same(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
