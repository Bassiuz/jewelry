import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jewelry_binding.dart';
import 'scenario_suite.dart';

/// `main` of the generated suite: declares the scenarios of every file in
/// [files], or only those of the file the CLI picked.
///
/// The app is built once with all scenario files in it. The CLI installs
/// that build for every file and says which one to run through
/// [suiteProperty], because a build has no other input at start.
void runScenarioSuite(Map<String, void Function()> files) {
  final binding = JewelryBinding.ensureInitialized();
  final only = _picked();
  for (final MapEntry(key: file, value: declare) in files.entries) {
    if (only == null || only == file) group(file, declare);
  }
  if (only == null) return;
  // Nothing on the host runs these tests, so nothing there knows when they
  // are over or how they went: say it in the log the CLI reads.
  tearDownAll(() {
    final failed = binding.failureMethodsDetails;
    for (final f in failed) {
      final said = (f.details ?? '')
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.startsWith('══'))
          .take(3)
          .join(' ');
      debugPrint('jewelry: uncaught error in "${f.methodName}": $said');
    }
    // ignore: avoid_print
    print('$suiteDoneMarker\t$only\t${failed.length}');
  });
}

/// The file the CLI picked, or null when `flutter test --name` picks (iOS)
/// or everything runs.
String? _picked() {
  if (!Platform.isAndroid) return null;
  final value = (Process.runSync('getprop', [suiteProperty]).stdout as String)
      .trim();
  return value.isEmpty ? null : value;
}
