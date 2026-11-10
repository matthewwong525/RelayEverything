import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/web/sign_in.dart';
import 'package:relay_app/web/space.dart';

// The browser's sign-in, with a stand-in server, as SignIn.test.tsx tested the React page.
const email = 'ana@example.com';
final base = Uri.parse('https://relay.example.com/apps/relay/');

http.Response json(Object body, [int status = 200]) =>
  http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
http.Response refused(int status, String message) => json({'error': {'code': 'forbidden', 'message': message}}, status);

class Server {
  http.Response Function() methods = () => json({'email': true, 'apple': true, 'google': true, 'signUp': true});
  http.Response Function(Map<String, dynamic> body) email = (_) => json({'sent': true});
  final posts = <String, List<Map<String, dynamic>>>{};

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/apps/relay/sign-in/methods') return methods();
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      posts.putIfAbsent(path, () => []).add(body);
      if (path == '/apps/relay/sign-in/email') return email(body);
      if (path == '/apps/relay/sign-in/code') {
        return body['code'] == '123456' ? json({'ok': true}) : refused(401, 'That code is wrong.');
      }
    }
    throw StateError('Unexpected request: ${request.method} ${request.url}');
  });
}

class Opened {
  int signedIn = 0;
  final navigated = <Uri>[];
}

Future<Opened> open(WidgetTester tester, Server server, {String page = 'https://relay.example.com/apps/relay/'}) async {
  final opened = Opened();
  await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light), home: SignInScreen(
    client: SpaceClient(base: base, client: server.client),
    onSignedIn: () => opened.signedIn++,
    page: Uri.parse(page),
    navigate: (address) async => opened.navigated.add(address),
  )));
  await tester.pumpAndSettle();
  return opened;
}

Future<void> signInWithCode(WidgetTester tester, [String code = '123456']) async {
  await tester.enterText(find.widgetWithText(TextField, 'Email'), ' $email ');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Email me a code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Code'), '${code}x');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, String label) =>
  tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, label)).onPressed != null;

void main() {
  testWidgets('shows each way in, then signs in with an email code', (tester) async {
    final server = Server();
    final opened = await open(tester, server);
    expect(find.text('Sign in or make an account'), findsOneWidget);
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('New here? The same steps make your account.'), findsOneWidget);
    expect(find.text('That sign-in did not work. Try again.'), findsNothing);
    expect(enabled(tester, 'Email me a code'), isFalse);

    await signInWithCode(tester, '654321');
    expect(find.text('That code is wrong.'), findsOneWidget);
    expect(opened.signedIn, 0);
    await tester.tap(find.text('Use another email'));
    await tester.pumpAndSettle();
    await signInWithCode(tester);

    expect(opened.signedIn, 1);
    expect(opened.navigated, isEmpty);
    expect(server.posts['/apps/relay/sign-in/email'], [{'email': email}, {'email': email}]);
    expect(server.posts['/apps/relay/sign-in/code'], [{'email': email, 'code': '654321'}, {'email': email, 'code': '123456'}]);
  });

  testWidgets('the code field takes six digits only', (tester) async {
    final server = Server();
    await open(tester, server);
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Email me a code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('We sent a code to', findRichText: true), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '12a34');
    await tester.pump();
    expect(enabled(tester, 'Sign in'), isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '1234567');
    await tester.pump();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Code')).controller!.text, '123456');
    expect(enabled(tester, 'Sign in'), isTrue);
  });

  testWidgets('hides Apple, Google and sign-up when the server has them off, and shows the refusal', (tester) async {
    final server = Server()
      ..methods = (() => json({'email': true, 'apple': false, 'google': false, 'signUp': false}))
      ..email = ((_) => refused(403, 'Sign-up is closed on this server.'));
    await open(tester, server, page: 'https://relay.example.com/apps/relay/?signIn=failed');
    expect(find.text('That sign-in did not work. Try again.'), findsOneWidget);
    expect(find.text('Sign in with Apple'), findsNothing);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.text('or'), findsNothing);
    expect(find.textContaining('New here'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Email me a code'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-up is closed on this server.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Code'), findsNothing);
  });

  testWidgets('shows only Apple when only Apple is on', (tester) async {
    final server = Server()..methods = (() => json({'email': false, 'apple': true, 'google': false, 'signUp': true}));
    await open(tester, server);
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
  });

  testWidgets('Apple and Google open in the same window and come back to the page', (tester) async {
    final opened = await open(tester, Server());
    await tester.tap(find.text('Sign in with Apple'));
    await tester.tap(find.text('Sign in with Google'));
    expect(opened.navigated.map((uri) => uri.toString()), [
      'https://relay.example.com/apps/relay/sign-in/apple?next=%2Fapps%2Frelay%2F',
      'https://relay.example.com/apps/relay/sign-in/google?next=%2Fapps%2Frelay%2F',
    ]);
  });

  testWidgets("goes back to the AI connector's own page after signing in, and never to another site", (tester) async {
    const next = '/apps/relay/sign-in/connect?state=s1';
    var opened = await open(tester, Server(),
      page: 'https://relay.example.com/apps/relay/?next=${Uri.encodeQueryComponent(next)}');
    await tester.tap(find.text('Sign in with Apple'));
    expect(opened.navigated.single.queryParameters['next'], next);
    expect(opened.navigated.single.path, '/apps/relay/sign-in/apple');
    opened.navigated.clear();
    await signInWithCode(tester);
    expect(opened.navigated.single.toString(), 'https://relay.example.com$next');
    expect(opened.signedIn, 0);

    await tester.pumpWidget(const SizedBox());
    opened = await open(tester, Server(), page: 'https://relay.example.com/apps/relay/?next=https%3A%2F%2Fevil.example.com%2F');
    await tester.tap(find.text('Sign in with Google'));
    expect(opened.navigated.single.queryParameters['next'], '/apps/relay/');
    opened.navigated.clear();
    await signInWithCode(tester);
    expect(opened.navigated, isEmpty);
    expect(opened.signedIn, 1);
  });

  testWidgets('a next that is the page itself just signs in', (tester) async {
    final opened = await open(tester, Server(), page: 'https://relay.example.com/apps/relay/?next=%2Fapps%2Frelay%2F');
    await signInWithCode(tester);
    expect(opened.navigated, isEmpty);
    expect(opened.signedIn, 1);
  });

  testWidgets("shows the server's contact address only when it has one", (tester) async {
    await open(tester, Server());
    expect(find.textContaining('Questions or privacy requests'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final server = Server()..methods = (() =>
      json({'email': true, 'apple': true, 'google': true, 'signUp': true, 'contact': 'privacy@relayeverything.com'}));
    final opened = await open(tester, server);
    expect(find.textContaining('Questions or privacy requests'), findsOneWidget);
    await tester.ensureVisible(find.text('privacy@relayeverything.com'));
    await tester.tap(find.text('privacy@relayeverything.com'));
    expect(opened.navigated.single.toString(), 'mailto:privacy@relayeverything.com');
  });

  testWidgets('says to reload the page where Access signs people in', (tester) async {
    final server = Server()..methods = (() => http.Response('Not found', 404));
    await open(tester, server);
    expect(find.textContaining('Reload this page'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
    expect(find.text('Sign in with Apple'), findsNothing);
  });

  testWidgets('says when the server did not answer, and reads it again', (tester) async {
    var down = true;
    final server = Server();
    final first = server.methods;
    server.methods = () => down ? http.Response('down', 502) : first();
    await open(tester, server);
    expect(find.text(noAnswer), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    down = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in or make an account'), findsOneWidget);
  });
}
