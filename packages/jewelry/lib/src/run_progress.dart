import 'dart:async';
import 'dart:io';

import 'scenario_result.dart';

/// What the CLI shows during a run: one line per finished scenario and, on a
/// terminal, a footer with the progress bar, the counts, the time and, per
/// emulator, the scenario and step it is at. Piped into a file it prints
/// plain lines instead, steps included.
class RunProgress {
  RunProgress({
    required this.total,
    this.estimate,
    this.workers = 1,
    StringSink? sink,
    bool? live,
    this.columns,
  }) : _out = sink ?? stdout,
       _live = live ?? stdout.hasTerminal {
    if (_live) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _redraw());
    }
  }

  /// Scenario files in this run.
  final int total;

  /// What the same files took last time, when known.
  final Duration? estimate;

  /// Emulators running scenarios at the same time.
  final int workers;

  /// Footer width; the terminal's when null.
  final int? columns;

  final StringSink _out;
  final bool _live;
  final _clock = Stopwatch()..start();
  Timer? _ticker;

  /// Lines of footer on screen.
  var _footerLines = 0;
  var _done = 0;
  var _passed = 0;
  var _failed = 0;
  var _status = 'starting';

  /// What each emulator is running, by worker.
  final _running = <int, ({String name, Stopwatch clock})>{};
  final _steps = <int, String>{};

  static const _red = '\x1b[31m';
  static const _green = '\x1b[32m';
  static const _yellow = '\x1b[33m';
  static const _bold = '\x1b[1m';
  static const _dim = '\x1b[2m';
  static const _reset = '\x1b[0m';

  Duration get elapsed => _clock.elapsed;

  String _paint(String text, String colour) =>
      _live ? '$colour$text$_reset' : text;

  /// A line above the footer.
  void line(String text) {
    _erase();
    _out.writeln(text);
    _draw();
  }

  /// What the run is doing between scenarios: booting, starting emulators.
  void status(String text) {
    _status = text;
    if (_live) {
      _redraw();
    } else {
      _out.writeln('== $text');
    }
  }

  /// Which emulator a plain line is about, when there are several.
  String _tag(int worker) => workers > 1 ? '[${worker + 1}] ' : '';

  /// A scenario file starts on emulator [worker].
  void start(String name, {int worker = 0}) {
    _running[worker] = (name: name, clock: Stopwatch()..start());
    _steps.remove(worker);
    if (_live) {
      _redraw();
    } else {
      _out.writeln(
        '== ${_tag(worker)}[${_done + _running.length}/$total] $name',
      );
    }
  }

  /// The scenario running on emulator [worker] entered a step.
  void step(String label, {int worker = 0}) {
    final running = _running[worker];
    if (running == null) return;
    _steps[worker] = label;
    if (_live) {
      _redraw();
    } else {
      _out.writeln(
        '   ${_tag(worker)}${clock(running.clock.elapsed)} step: $label',
      );
    }
  }

  /// The scenario file on emulator [worker] is done, with these results.
  void finish(List<ScenarioResult> results, {int worker = 0}) {
    _done++;
    _running.remove(worker);
    for (final r in results) {
      r.failed ? _failed++ : _passed++;
      final time = clock(r.duration);
      line(
        r.failed
            ? '${_paint('✗', _red)} ${r.label}  ${_paint(time, _dim)}  '
                  '${_paint(r.reason, _red)}'
            : '${_paint('✓', _green)} ${r.label}  ${_paint(time, _dim)}  '
                  '${_paint('${r.outcome.name}, ${r.frames} frames, '
                      '${r.snapshots} snapshots', _dim)}',
      );
    }
  }

  /// Removes the footer and stops the clock.
  void close() {
    _ticker?.cancel();
    _erase();
  }

  /// The closing report: every failure with its reason, where to look and
  /// how to rerun it, then the counts.
  void summary(List<ScenarioResult> results, {required String dart}) {
    final failures = [for (final r in results) if (r.failed) r];
    final rule = '─' * 60;
    _out
      ..writeln()
      ..writeln(rule)
      ..writeln(_paint(' Jewelry run summary', _bold))
      ..writeln(rule);
    if (failures.isNotEmpty) {
      _out.writeln('\n${_paint(' FAILED', '$_bold$_red')}\n');
    }
    for (final r in failures) {
      _out.writeln('${_paint('✗ ${r.label}', _red)}  [${r.profile}]');
      _out.writeln('  ${_paint(r.reason, _bold)}');
      for (final l in r.detail.split('\n').where((l) => l.isNotEmpty)) {
        _out.writeln('  $l');
      }
      if (Directory('.jewelry/${r.failureDir}').existsSync()) {
        _out.writeln('  Evidence: .jewelry/${r.failureDir}/');
      }
      if (r.log != null) _out.writeln('  Log:      .jewelry/${r.log}');
      _out.writeln(
        '  Rerun:    ${_paint('$dart run jewelry run ${r.file}', _yellow)}',
      );
      _out.writeln();
    }
    final passed = results.length - failures.length;
    _out
      ..writeln(
        '${_paint('$passed passed', _green)}, '
        '${_paint('${failures.length} failed', failures.isEmpty ? _dim : _red)}, '
        'Total: ${results.length}, Duration: ${clock(elapsed)}',
      )
      ..writeln(rule)
      ..writeln('Report: ${File('.jewelry/report.html').absolute.uri}');
    if (failures.isNotEmpty) {
      _out.writeln(
        'Rerun the failures: ${_paint('$dart run jewelry run --failed', _yellow)}',
      );
    }
    if (failures.any((r) => r.acceptable)) {
      _out.writeln(
        'Make the new recordings the goldens: '
        '${_paint('$dart run jewelry accept', _yellow)}',
      );
    }
    _out.writeln(rule);
  }

  void _redraw() {
    _erase();
    _draw();
  }

  void _erase() {
    if (_footerLines == 0) return;
    _out.write('\r\x1b[K${'\x1b[1A\r\x1b[K' * (_footerLines - 1)}');
    _footerLines = 0;
  }

  void _draw() {
    if (!_live) return;
    // A pty without a size reports 0 columns.
    var width = (columns ?? stdout.terminalColumns) - 1;
    if (width < 40) width = 79;
    final fraction = total == 0 ? 0.0 : _done / total;
    const barWidth = 24;
    final filled = (fraction * barWidth).round();
    final time = estimate == null
        ? clock(elapsed)
        : '${clock(elapsed)} / ~${clock(estimate!)}';
    var counts =
        ' $_done/$total · $_passed passed · $_failed failed · $time';
    final where = _running.isEmpty
        ? [_status]
        : [
            for (final MapEntry(key: worker, value: r)
                in (_running.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key))))
              '▶ ${_tag(worker)}${r.name} · ${clock(r.clock.elapsed)}'
                  '${_steps[worker] == null ? '' : ' · ${_steps[worker]}'}',
          ];
    // A wrapped footer line would break the cursor arithmetic in _erase.
    if (counts.length > width - barWidth - 2) {
      counts = counts.substring(0, (width - barWidth - 2).clamp(0, counts.length));
    }
    if (_failed > 0) {
      counts = counts.replaceFirst('$_failed failed', '$_red$_failed failed$_reset');
    }
    _out.write(
      '[$_green${'█' * filled}$_reset${'░' * (barWidth - filled)}]$counts\n'
      '$_dim${where.map((l) => l.length > width ? l.substring(0, width) : l).join('\n')}$_reset',
    );
    _footerLines = 1 + where.length;
  }

  /// `mm:ss`, or `h:mm:ss` from an hour on.
  static String clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final rest = '${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return d.inHours > 0 ? '${d.inHours}:$rest' : rest;
  }
}
