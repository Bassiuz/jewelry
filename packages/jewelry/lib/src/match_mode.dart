/// How a run is compared against its golden recording.
enum MatchMode {
  /// Every frame, in order, within the drift window. For apps whose frames
  /// are the same every run.
  frames,

  /// The screens the run rests on, in order. For apps with wall-clock
  /// timers and network, where frame counts differ between runs.
  screens,
}
