## 0.0.2

- Dashboard: a third picture next to the golden and this run marks in red what differs, live while playing or scrubbing.
- Dashboard: lighter overlays for ignored areas and waiting frames, so the screen underneath stays readable.

## 0.0.1

First release.

- Scenario DSL: `scenario`, `step`, keys, `text()`, `field()`, and `t.snapshot()` for image goldens.
- Every engine frame captured on a harness-driven clock; an app clock through `package:clock`, and the app's own timers on that clock.
- Compare by frames or by resting screens, with ignored regions for widgets that animate on their own clock.
- Device actions on Android: background, lock screen, notification taps, permissions, app ops.
- CLI: `run` (build once, parallel emulators, headless, offline by default), `accept`, `video`, `dashboard`, `devices`.
- Live dashboard with synced golden/run playback, stops at each difference, ignored areas drawn on the video, a hoverable step bar, and accept.
- HTML report and `.jewelry/` evidence folders.
