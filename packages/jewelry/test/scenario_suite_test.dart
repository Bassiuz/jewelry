import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/src/scenario_suite.dart';

void main() {
  test('one group per scenario file, in a stable order', () {
    final suite = ScenarioSuite([
      './integration_test/scenarios/b_test.dart',
      'integration_test/scenarios/a_test.dart',
      'integration_test/scenarios/b_test.dart',
    ]);
    expect(suite.files, [
      'integration_test/scenarios/a_test.dart',
      'integration_test/scenarios/b_test.dart',
    ]);
    expect(suite.source, contains("import 'scenarios/a_test.dart' as s0;"));
    expect(suite.source, contains("'scenarios/b_test.dart': s1.main,"));
  });

  test('the name pattern picks one file, not one that ends the same', () {
    final name = RegExp(
      ScenarioSuite.nameOf('integration_test/scenarios/note_test.dart'),
    );
    expect(name.hasMatch('scenarios/note_test.dart Diary note'), isTrue);
    expect(name.hasMatch('scenarios/diary_note_test.dart Diary note'), isFalse);
    expect(name.hasMatch('scenarios/noteXtest.dart Diary note'), isFalse);
  });

  test('a file outside integration_test is refused', () {
    expect(() => ScenarioSuite(['test/a_test.dart']), throwsArgumentError);
  });
}
