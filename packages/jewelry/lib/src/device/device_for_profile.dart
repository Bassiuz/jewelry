import '../device_profile.dart';
import 'android_device.dart';
import 'device.dart';
import 'ios_device.dart';

/// [window] shows the Android emulator window; a simulator never opens one.
/// [instance] is set when several emulators of the profile run at once.
Device deviceForProfile(DeviceProfile p, {bool window = false, int? instance}) =>
    switch (p.platform) {
      'android' => AndroidDevice(
        p.avd!,
        ramMb: p.ramMb,
        internet: p.internet,
        window: window,
        instance: instance,
      ),
      _ => IosDevice(p.simulator!, p.runtime!),
    };
