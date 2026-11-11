<p align="center"><img src="logo.svg" width="128" alt="jewelry logo: a gold ring with a diamond"></p>

<h1 align="center">jewelry</h1>

<p align="center">Video goldens for Flutter integration tests.</p>

Write a scenario as plain Dart steps. jewelry boots a clean emulator, runs the
scenario, captures every engine frame, and compares the result frame by frame
against a recorded golden. Mismatches are reported like widget goldens: expected,
actual, diff, plus the step and frame where it went wrong.

Two packages, one repo:

- [`packages/jewelry`](packages/jewelry): the core. Scenario DSL, actions, frame capture, comparator, report, dashboard, CLI. Its [README](packages/jewelry/README.md) is the full guide, and what pub.dev shows.
- [`packages/jewelry_firebase`](packages/jewelry_firebase): runs the app against the Firebase Emulator Suite, seeds data and fakes Cloud Functions.
- `example/`: a small app with scenarios that double as the packages' own end-to-end tests.

<img src="doc/golden.gif" width="240" alt="A recorded golden: log in as anna, land on the home screen, open the notes tab and see Groceries">

## Development

Flutter is pinned with fvm (`.fvmrc`). Always use `fvm flutter`.

```
fvm flutter pub get
```
