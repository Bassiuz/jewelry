import 'scenario_tester.dart';

/// The body of a [Step]: drives the app through [t].
typedef StepBody = Future<void> Function(ScenarioTester t);

/// A labelled, reusable unit of a scenario.
///
/// Plain value: define it once in `integration_test/steps/` and import it
/// into any scenario.
class Step {
  const Step(this.label, this.run);

  final String label;
  final StepBody run;
}

/// Creates a [Step].
Step step(String label, StepBody run) => Step(label, run);
