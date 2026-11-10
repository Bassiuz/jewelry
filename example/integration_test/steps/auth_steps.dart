import 'package:jewelry/jewelry.dart';

Step logInAs(String email, String password) =>
    step('Log in as $email', (t) async {
      await t.enterText('emailField', email);
      await t.enterText('passwordField', password);
      await t.tap('loginButton');
      await t.waitFor('home');
    });
