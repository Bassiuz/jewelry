## 0.0.1

First release.

- Scenario DSL: `scenario`, `step`, keys, `text()`, `field()`, and `t.snapshot()` for image goldens.
- Every engine frame captured on a harness-driven clock; an app clock through `package:clock`.
- Compare by frames or by resting screens, with ignored regions for widgets that animate on their own clock.
- Device actions on Android: background, lock screen, notification taps, permissions, app ops.
- CLI: `run` (build once, parallel emulators, headless, offline by default), `accept`, `video`, `dashboard`, `devices`.
- Live dashboard with synced golden/run playback, stops at each difference, and accept.
- HTML report and `.jewelry/` evidence folders.
