# Decisions

All decisions for this package are kept in the repository root `decisions.md`.
- **Android emulators run offline.** Added on 2026-11-10. Firebase is reached on 127.0.0.2 through `adb reverse` and the fakes through `adb forward`, so a scenario needs no network. Wi-Fi and mobile data are switched off after boot; `internet: true` on a profile keeps them and then checks the emulator really has internet. Apps that check for internet themselves must be told they are online (MedApp does this under its `JEWELRY` define).
- **The top inset is pinned to 24 dp on Android.** Added on 2026-11-10. Emulators of one AVD report either the status bar alone (72 px on a Pixel 8 Pro) or the status bar plus the camera cutout (151 px), per boot, which shifted every screen 26 frame pixels between goldens. Each scenario sets the test view's top padding and view padding to 24 dp; device screenshots are untouched.
