import 'dart:convert';
import 'dart:typed_data';

import 'host_channel.dart';

/// `t.device`: actions the host performs on the emulator or simulator.
///
/// Nothing here pumps frames. While the app is in the background the engine
/// produces no frames, so use [ScenarioTester.wait] there, not pump.
class DeviceActions {
  DeviceActions(this._channel, this._onBackgroundChanged, this._onShot);

  final HostChannel _channel;
  final void Function(bool backgrounded) _onBackgroundChanged;
  final Future<void> Function(Uint8List png) _onShot;

  /// Sends the app to the background (home on Android, another app on iOS).
  Future<void> background() async {
    await _channel.request('background');
    _onBackgroundChanged(true);
  }

  /// Brings the app back to the foreground.
  Future<void> foreground() async {
    await _channel.request('foreground');
    _onBackgroundChanged(false);
  }

  /// Takes a screenshot of the whole device screen, including notifications
  /// and system UI the in-process frames never show. Saved by the CLI under
  /// `.jewelry/shots/<scenario>/<profile>/` as evidence; not compared.
  ///
  /// With [shade] the notification shade is opened first and closed after,
  /// so the shot shows the notifications. Android only.
  ///
  /// The shot is also added to the recording as a device frame.
  Future<Uint8List> screenshot(String label, {bool shade = false}) async {
    final png = await rawScreenshot(label: label, shade: shade);
    await _onShot(png);
    return png;
  }

  /// A device screenshot without adding it to the recording. Without a
  /// [label] it is not saved under `.jewelry/shots/` either.
  Future<Uint8List> rawScreenshot({String? label, bool shade = false}) async {
    final result =
        await _channel.request('screenshot', {
              'label': ?label,
              'shade': shade,
            })
            as String;
    return base64Decode(result);
  }

  /// Grants a runtime permission to the app before it asks, so no system
  /// dialog appears. Android only (for example
  /// `android.permission.POST_NOTIFICATIONS`); a no-op on iOS.
  Future<void> grantPermission(String permission) =>
      _channel.request('grantPermission', {'permission': permission});

  /// Presses the system back button. Android only. The app keeps running,
  /// so [ScenarioTester.settle] afterwards records the pop.
  Future<void> back() => _channel.request('back');

  /// Turns the screen off (locks the device) or wakes it. Android only.
  /// With the screen off a full-screen-intent notification launches its
  /// activity instead of a heads-up.
  Future<void> screenOff() async {
    await _channel.request('screenOff');
    _onBackgroundChanged(true);
  }

  /// Locks the phone with the screen on: the keyguard shows, the app is
  /// stopped behind it. A full-screen-intent notification then launches its
  /// activity over the lock screen. Android only.
  Future<void> lockScreen() async {
    await _channel.request('lockScreen');
    _onBackgroundChanged(true);
  }

  Future<void> screenOn() async {
    await _channel.request('screenOn');
    _onBackgroundChanged(false);
  }

  /// Sets an app op for the app, for example `USE_FULL_SCREEN_INTENT` to
  /// `allow`, which Android 14+ does not grant by default. Android only.
  Future<void> setAppOp(String op, String mode) =>
      _channel.request('setAppOp', {'op': op, 'mode': mode});

  /// Opens the notification shade and taps the action or notification whose
  /// text matches [text] (case-insensitive). Android only.
  Future<void> tapNotificationAction(String text) =>
      _channel.request('tapNotificationAction', {'text': text});
}
