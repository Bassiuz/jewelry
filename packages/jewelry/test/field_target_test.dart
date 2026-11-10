import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry/jewelry.dart';

void main() {
  Widget form(List<Widget> children) => MaterialApp(
    home: Scaffold(body: Column(children: children)),
  );

  testWidgets('finds a field by the label inside it', (tester) async {
    await tester.pumpWidget(
      form([
        const TextField(decoration: InputDecoration(labelText: 'E-mail')),
        const TextField(decoration: InputDecoration(labelText: 'Wachtwoord')),
      ]),
    );
    await tester.enterText(field('Wachtwoord').finder, 'x');
    expect(
      tester.widget<TextField>(field('Wachtwoord').finder).controller,
      isNull,
    );
    expect(field('Wachtwoord').finder, findsOneWidget);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('finds the field right below a label above it', (tester) async {
    final a = TextEditingController();
    final b = TextEditingController();
    await tester.pumpWidget(
      form([
        const Text('Beschrijving'),
        TextField(controller: a),
        const Text('Naam'),
        TextField(controller: b),
      ]),
    );
    await tester.enterText(field('Naam').finder, 'Anna');
    await tester.enterText(field('Beschrijving').finder, 'Notitie');
    expect(b.text, 'Anna');
    expect(a.text, 'Notitie');
  });

  testWidgets('matches nothing when the label is absent', (tester) async {
    await tester.pumpWidget(form([const TextField()]));
    expect(field('Nergens').finder, findsNothing);
  });
}
