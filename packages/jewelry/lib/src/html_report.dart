import 'dart:convert';
import 'dart:io';

import 'run_log.dart';
import 'run_progress.dart';

/// Writes `.jewelry/report.html`: every scenario of [log], failures first.
///
/// A failure shows its reason, the failing frame of the golden next to the
/// run's with the differing pixels in red, every snapshot that changed the
/// same way, the frames per step of both, and both recordings to play. All
/// of it is read from the failure folders, so the page is one static file
/// with relative links.
void writeHtmlReport(RunLog log, {required String dart}) {
  final failed = [for (final r in log.results) if (r.failed) r];
  final fine = [for (final r in log.results) if (!r.failed) r]
    ..sort((a, b) => a.label.compareTo(b.label));
  final latest = log.results
      .map((r) => r.ranAt)
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  final root = log.dir.path;

  final html = StringBuffer('''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jewelry report</title>
<style>
  :root { color-scheme: light dark; --line: #8884; --bad: #d1242f; --ok: #1a7f37; --soft: #8882; }
  body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0 auto; max-width: 1100px; padding: 24px 16px 80px; }
  h1 { font-size: 22px; margin: 0; }
  h2 { font-size: 16px; margin: 32px 0 12px; }
  h3 { font-size: 16px; margin: 0 0 4px; }
  h4 { font-size: 13px; margin: 20px 0 8px; text-transform: uppercase; letter-spacing: .04em; opacity: .7; }
  .meta { opacity: .7; font-size: 13px; font-weight: normal; }
  .ok { color: var(--ok); } .bad { color: var(--bad); }
  article { border: 1px solid var(--line); border-left: 4px solid var(--bad); border-radius: 8px; padding: 16px; margin-bottom: 20px; }
  .reason { font-weight: 600; margin: 8px 0; }
  pre { background: var(--soft); border-radius: 6px; padding: 10px; white-space: pre-wrap; word-break: break-word; font-size: 12px; margin: 8px 0; }
  code { background: var(--soft); border-radius: 4px; padding: 1px 5px; font-size: 12px; }
  .frames { display: flex; flex-wrap: wrap; gap: 12px; }
  figure { margin: 0; text-align: center; font-size: 12px; }
  figure img { display: block; width: 240px; max-width: 100%; border: 1px solid var(--line); border-radius: 6px; }
  table { border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 3px 14px 3px 0; border-bottom: 1px solid var(--line); }
  td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
  tr.at td { color: var(--bad); font-weight: 600; }
  tr.off td.n { font-weight: 600; }
  details { margin-top: 12px; }
  summary { cursor: pointer; }
  .passed details { border-bottom: 1px solid var(--line); margin: 0; padding: 6px 0; }
  .passed .frames { padding: 12px 0; }
  .how p { margin: 4px 0; font-size: 13px; }
</style>
</head>
<body>
<h1>Jewelry report</h1>
<p><span class="${failed.isEmpty ? 'ok' : 'bad'}">${failed.length} failed</span> · <span class="ok">${fine.length} passed</span> · ${log.results.length} scenarios${latest == null ? '' : ' · latest run ${_when(latest)}'}</p>
''');

  if (failed.isNotEmpty) html.writeln('<h2>Failed</h2>');
  for (final r in failed) {
    final dir = '$root/${r.failureDir}';
    bool has(String name) => File('$dir/$name').existsSync();
    html.writeln('<article>');
    html.writeln(
      '<h3><span class="bad">✗</span> ${_e(r.label)} '
      '<span class="meta">${_e(r.profile)} · ${RunProgress.clock(r.duration)} '
      '· ${_when(r.ranAt)}</span></h3>',
    );
    html.writeln('<p class="reason">${_e(r.reason)}</p>');
    if (r.detail.isNotEmpty) html.writeln('<pre>${_e(r.detail)}</pre>');

    if (has('expected_frame.png') && has('diff.png')) {
      html.writeln('<h4>The frame it failed on</h4><div class="frames">');
      html.writeln(_figure('${r.failureDir}/expected_frame.png', 'Expected (golden)'));
      html.writeln(_figure('${r.failureDir}/actual_frame.png', 'Actual (this run)'));
      html.writeln(_figure('${r.failureDir}/diff.png', 'Difference in red'));
      html.writeln('</div>');
    } else if (has('actual_frame.png')) {
      html.writeln('<h4>Where it stopped</h4><div class="frames">');
      html.writeln(_figure('${r.failureDir}/actual_frame.png', 'Last frame of the run'));
      html.writeln('</div>');
    }

    final shots = Directory('$dir/snapshots');
    if (shots.existsSync()) {
      final names = [
        for (final f in shots.listSync().whereType<File>())
          if (f.path.endsWith('.diff.png'))
            f.uri.pathSegments.last.replaceAll('.diff.png', ''),
      ]..sort();
      for (final name in names) {
        final base = '${r.failureDir}/snapshots/$name';
        html.writeln('<h4>Snapshot ${_e(name)}</h4><div class="frames">');
        html.writeln(_figure('$base.expected.png', 'Expected (golden)'));
        html.writeln(_figure('$base.actual.png', 'Actual (this run)'));
        html.writeln(_figure('$base.diff.png', 'Difference in red'));
        html.writeln('</div>');
      }
    }

    final golden = _steps(
      has('expected.steps.json')
          ? File('$dir/expected.steps.json')
          : File('$root/${r.goldenBase}.steps.json'),
    );
    final actual = _steps(File('$dir/actual.steps.json'));
    if (golden.isNotEmpty || actual.isNotEmpty) {
      html.writeln(
        '<h4>Compared frames per step</h4><table>'
        '<tr><th>Step</th><th class="n">Golden</th><th class="n">This run</th></tr>',
      );
      for (final step in {...golden.keys, ...actual.keys}) {
        final g = golden[step];
        final a = actual[step];
        final cls = step == r.step ? 'at' : (g != a ? 'off' : '');
        html.writeln(
          '<tr class="$cls"><td>${_e(step)}</td>'
          '<td class="n">${g ?? '–'}</td><td class="n">${a ?? '–'}</td></tr>',
        );
      }
      html.writeln('</table>');
    }

    if (has('actual.apng')) {
      html.writeln('<details><summary>Play the recordings</summary><div class="frames">');
      if (has('expected.apng')) {
        html.writeln(_figure('${r.failureDir}/expected.apng', 'Expected (golden)'));
      }
      html.writeln(_figure('${r.failureDir}/actual.apng', 'Actual (this run)'));
      html.writeln('</div></details>');
    }

    html.writeln('<div class="how">');
    if (r.acceptable) {
      html.writeln(
        '<p>Looks right? Make it the golden: '
        '<code>$dart run jewelry accept "${_e(r.label)}"</code></p>',
      );
    }
    html.writeln('<p>Rerun: <code>$dart run jewelry run ${_e(r.file)}</code></p>');
    if (r.log != null) {
      html.writeln('<p><a href="${_e(r.log!)}">flutter test output</a></p>');
    }
    html.writeln('</div></article>');
  }

  if (fine.isNotEmpty) html.writeln('<h2>Passed</h2><div class="passed">');
  for (final r in fine) {
    html.writeln(
      '<details><summary><span class="ok">✓</span> ${_e(r.label)} '
      '<span class="meta">${_e(r.profile)} · ${r.outcome.name} · '
      '${RunProgress.clock(r.duration)} · ${r.frames} frames · '
      '${r.snapshots} snapshots</span></summary><div class="frames">',
    );
    html.writeln(_figure('${r.goldenBase}.apng', 'Golden recording'));
    final shots = Directory('$root/${r.goldenBase}');
    if (shots.existsSync()) {
      final files = [
        for (final f in shots.listSync().whereType<File>())
          if (f.path.endsWith('.png')) f.uri.pathSegments.last,
      ]..sort();
      for (final f in files) {
        html.writeln(_figure('${r.goldenBase}/$f', f.replaceAll('.png', '')));
      }
    }
    html.writeln('</div></details>');
  }
  if (fine.isNotEmpty) html.writeln('</div>');
  html.writeln('</body></html>');
  File('$root/report.html').writeAsStringSync(html.toString());
}

/// Compared frames per step, in order: no device or wait frames.
Map<String, int> _steps(File sidecar) {
  final steps = <String, int>{};
  if (!sidecar.existsSync()) return steps;
  for (final run in jsonDecode(sidecar.readAsStringSync()) as List) {
    final compared = run['device'] != true && run['wait'] != true;
    steps.update(
      run['step'] as String,
      (n) => n + (compared ? run['frames'] as int : 0),
      ifAbsent: () => compared ? run['frames'] as int : 0,
    );
  }
  return steps;
}

// Lazy, so a closed <details> does not load a 30 MB recording.
String _figure(String src, String caption) =>
    '<figure><a href="${_e(src)}"><img loading="lazy" src="${_e(src)}" '
    'alt="${_e(caption)}"></a><figcaption>${_e(caption)}</figcaption></figure>';

// Slashes stay: the same text is used for paths in src and href.
String _e(String text) => const HtmlEscape(
  HtmlEscapeMode(name: 'report', escapeLtGt: true, escapeQuot: true),
).convert(text);

String _when(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
