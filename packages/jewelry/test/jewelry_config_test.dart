import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/jewelry_config.dart';
import 'package:jewelry/src/match_mode.dart';

void main() {
  test('parses profiles and defaults', () {
    final c = JewelryConfig.parse('''
profiles:
  pixel:
    platform: android
    avd: Pixel_8
  iphone:
    platform: ios
    simulator: iPhone 16
    runtime: iOS 18.2
tolerance: 0.5
''');
    expect(c.profiles['pixel']!.avd, 'Pixel_8');
    expect(c.profiles['iphone']!.runtime, 'iOS 18.2');
    expect(c.drift, 30);
    expect(c.tolerance, 0.5);
    expect(c.match, MatchMode.frames);
  });

  test('parses the screens match mode and rejects an unknown one', () {
    final c = JewelryConfig.parse('profiles: {}\nmatch: screens\nrest: 20\n');
    expect(c.match, MatchMode.screens);
    expect(c.rest, 20);
    expect(
      () => JewelryConfig.parse('profiles: {}\nmatch: fuzzy\n'),
      throwsFormatException,
    );
  });

  test('run defaults: headless, one emulator, every profile', () {
    final c = JewelryConfig.parse('profiles: {}\n');
    expect(c.headless, isTrue);
    expect(c.parallel, 1);
    expect(c.defaultProfile, isNull);
  });

  test('the starter file parses and sets the run defaults', () {
    final c = JewelryConfig.parse(JewelryConfig.starter(['Pixel_8_Pro_API_35']));
    expect(c.profiles['pixel_8_pro_api_35']!.avd, 'Pixel_8_Pro_API_35');
    expect(c.defaultProfile, 'pixel_8_pro_api_35');
    expect(c.headless, isTrue);
    expect(c.parallel, 5);
  });

  test('a default profile that does not exist is refused', () {
    expect(
      () => JewelryConfig.parse('profiles: {}\ndefault_profile: pixel\n'),
      throwsFormatException,
    );
  });

  test('every worker gets its own firebase ports and config', () {
    final c = JewelryConfig.parse('''
profiles: {}
firebase:
  project: demo
''');
    final second = c.firebase!.forWorker(1);
    expect(c.firebase!.forWorker(0).firestorePort, 8080);
    expect(second.firestorePort, 8090);
    expect(second.dartDefines, contains('--dart-define=JEWELRY_FIREBASE_AUTH_PORT=9109'));
    final json = jsonDecode(
      second.firebaseJson('{"firestore": {"rules": "firestore.rules"}, '
          '"emulators": {"auth": {"port": 9099}, "singleProjectMode": true}}'),
    ) as Map;
    expect(json['firestore'], {'rules': 'firestore.rules'});
    expect(json['emulators']['auth'], {'port': 9109});
    expect(json['emulators']['firestore']['port'], 8090);
    expect(json['emulators']['hub'], {'port': 4410});
    expect(json['emulators']['singleProjectMode'], true);
  });

  test('parses the firebase block and flutter test args', () {
    final c = JewelryConfig.parse('''
profiles: {}
firebase:
  project: my-app-dev
  only: [auth, firestore, functions]
flutter_test_args: [--flavor, develop]
''');
    expect(c.firebase!.project, 'my-app-dev');
    expect(c.firebase!.only, ['auth', 'firestore', 'functions']);
    expect(
      c.firebase!.dartDefines,
      contains('--dart-define=JEWELRY_FIREBASE_PROJECT=my-app-dev'),
    );
    expect(c.flutterTestArgs, ['--flavor', 'develop']);
  });

  test('rejects an unknown platform', () {
    expect(
      () => JewelryConfig.parse('profiles:\n  x:\n    platform: web\n'),
      throwsFormatException,
    );
  });

  test('clock is read as an ISO date', () {
    final c = JewelryConfig.parse('''
profiles: {}
clock: 2026-01-05T09:00:00
''');
    expect(c.clock, DateTime(2026, 1, 5, 9));
  });
}
