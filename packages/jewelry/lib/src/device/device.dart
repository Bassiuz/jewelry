import 'dart:io';
import 'dart:typed_data';

/// An emulator or simulator the CLI owns for one run.
abstract class Device {
  /// Boots with wiped data. Returns the id to pass to `flutter test -d`.
  Future<String> boot();

  /// Whether this device exists on this machine.
  Future<bool> exists();

  /// Reads a file the on-device test wrote under its temp dir.
  Future<Uint8List> pull(String path);

  /// Clears the data of the app that wrote [anyAppPath].
  Future<void> clearApp(String anyAppPath);

  Future<void> shutdown();

  /// Streams the device log (logcat, or the simulator's unified log) to
  /// [to] until [stopLog]. Where a scenario that "did not complete" left
  /// its crash.
  Future<void> startLog(File to);

  Future<void> stopLog();

  /// Connects to the on-device host channel listening on [port].
  Future<Socket> connectChannel(int port);

  /// Sends the app that owns [anyAppPath] to the background.
  Future<void> background(String anyAppPath);

  /// Brings the app that owns [anyAppPath] to the foreground.
  Future<void> foreground(String anyAppPath);

  /// PNG of the whole device screen, with the notification shade open when
  /// [shade] is set.
  Future<Uint8List> screenshot({bool shade = false});

  /// Opens the notification shade and taps the element with [text].
  Future<void> tapNotificationAction(String text);

  Future<void> back();

  Future<void> screenOff();

  Future<void> screenOn();

  Future<void> lockScreen();

  /// Sets the device clock to [time] and stops network time from
  /// correcting it.
  Future<void> setClock(DateTime time);

  /// Makes [port] on the host reach [port] on the device, for servers the
  /// test runs on the device (fake Cloud Functions).
  Future<void> forwardToDevice(int port);

  Future<void> setAppOp(String anyAppPath, String op, String mode);

  /// Grants a runtime permission to the app that owns [anyAppPath].
  Future<void> grantPermission(String anyAppPath, String permission);
}
