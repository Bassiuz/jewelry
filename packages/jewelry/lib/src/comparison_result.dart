/// Outcome of [compareFrameSequences].
sealed class ComparisonResult {
  const ComparisonResult();
}

class ComparisonPassed extends ComparisonResult {
  const ComparisonPassed({required this.maxDrift});

  /// Largest lateness (in frames) any golden frame was found at.
  final int maxDrift;
}

/// A golden frame appears nowhere in the remaining actual frames.
class PixelMismatch extends ComparisonResult {
  const PixelMismatch({
    required this.goldenIndex,
    required this.actualIndex,
    required this.step,
    required this.diffPercent,
  });

  final int goldenIndex;

  /// The actual frame it was expected to match.
  final int actualIndex;
  final String step;
  final double diffPercent;

  @override
  String toString() =>
      'Pixel mismatch in step "$step": golden frame $goldenIndex vs actual '
      'frame $actualIndex (${diffPercent.toStringAsFixed(2)}% differs)';
}

/// A golden frame appears, but later than the drift window allows, or the
/// actual run has more trailing frames than the window allows.
class TimingFailure extends ComparisonResult {
  const TimingFailure({
    required this.goldenIndex,
    required this.actualIndex,
    required this.step,
    required this.drift,
  });

  final int goldenIndex;
  final int actualIndex;
  final String step;
  final int drift;

  @override
  String toString() =>
      'Timing failure in step "$step": golden frame $goldenIndex found at '
      'actual frame $actualIndex, $drift frames late';
}

/// Screens mode: one side rests on a screen the other never shows.
class ScreenMismatch extends ComparisonResult {
  const ScreenMismatch({
    required this.goldenIndex,
    required this.actualIndex,
    required this.step,
    required this.diffPercent,
    required this.missing,
    required this.frames,
  });

  /// Golden and actual frame to look at side by side: the screen in
  /// question and the closest screen on the other side.
  final int goldenIndex;
  final int actualIndex;
  final String step;
  final double diffPercent;

  /// True when the golden rests on a screen the run never shows; false when
  /// the run rests on a screen the golden never shows.
  final bool missing;

  /// How many frames the screen in question stays on.
  final int frames;

  @override
  String toString() => missing
      ? 'Screen missing in step "$step": the golden rests on frame '
            '$goldenIndex for $frames frames, the run never shows it. Closest '
            'is actual frame $actualIndex '
            '(${diffPercent.toStringAsFixed(2)}% differs)'
      : 'Unexpected screen in step "$step": the run rests on frame '
            '$actualIndex for $frames frames, the golden never shows it. '
            'Closest is golden frame $goldenIndex '
            '(${diffPercent.toStringAsFixed(2)}% differs)';
}
