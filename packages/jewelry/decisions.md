# Decisions

All decisions for this package are kept in the repository root `decisions.md`.
- **Android emulators run offline.** Added on 2026-11-10. Firebase is reached on 127.0.0.2 through `adb reverse` and the fakes through `adb forward`, so a scenario needs no network. Wi-Fi and mobile data are switched off after boot; `internet: true` on a profile keeps them and then checks the emulator really has internet. Apps that check for internet themselves must be told they are online (MedApp does this under its `JEWELRY` define).
