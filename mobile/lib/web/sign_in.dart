import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import 'navigate.dart';
import 'space.dart';

// Relay Everything's own sign-in in the browser: a code sent by email, or Apple or Google. The same steps make a new
// account. app/worker/apps/relay/sign-in/ answers; where Cloudflare Access signs people in, `methods` answers 404.

/// The ways in that the server has set up, and its contact address when it has one: sign-in/email.ts `methods`.
class SignInMethods {
  const SignInMethods({this.email = false, this.apple = false, this.google = false, this.signUp = false, this.contact});

  factory SignInMethods.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'];
    return SignInMethods(email: json['email'] == true, apple: json['apple'] == true, google: json['google'] == true,
      signUp: json['signUp'] == true, contact: contact is String && contact.isNotEmpty ? contact : null);
  }

  final bool email;
  final bool apple;
  final bool google;
  final bool signUp;
  final String? contact;
}

/// The page the AI connector asked to return to, only when it is one of Relay Everything's own.
String? nextOf(String? value) => value != null && value.startsWith('/apps/relay/') ? value : null;

/// The sign-in screen, shown in place of the app while nobody is signed in. [page] is the page's own address, which
/// can hold `next` and `signIn=failed`; [navigate] sends the window to another address, such as Apple's sign-in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.client, required this.onSignedIn, this.page, this.navigate});

  final SpaceClient client;
  final VoidCallback onSignedIn;
  final Uri? page;
  final Future<void> Function(Uri address)? navigate;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Load { loading, ready, access, failed }

class _SignInScreenState extends State<SignInScreen> {
  _Load _load = _Load.loading;
  SignInMethods _methods = const SignInMethods();
  final _email = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;

  Uri get _page => widget.page ?? Uri.base;
  String? get _next => nextOf(_page.queryParameters['next']);
  bool get _failed => _page.queryParameters['signIn'] == 'failed';
  Future<void> Function(Uri) get _navigate => widget.navigate ?? navigateTo;

  @override
  void initState() {
    super.initState();
    _email.addListener(_changed);
    _code.addListener(_changed);
    _read();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _read() async {
    setState(() => _load = _Load.loading);
    try {
      final json = await widget.client.getFrom(widget.client.signIn('methods'));
      if (!mounted) return;
      setState(() {
        _methods = SignInMethods.fromJson(json);
        _load = _Load.ready;
      });
    } on SpaceRefused catch (refused) {
      if (!mounted) return;
      setState(() => _load = refused.status == 404 ? _Load.access : _Load.failed);
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postTo(widget.client.signIn('email'), {'email': email});
      if (!mounted) return;
      setState(() {
        _sentTo = email;
        _code.clear();
      });
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() => _error = refused.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final email = _sentTo;
    if (email == null || _code.text.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postTo(widget.client.signIn('code'), {'email': email, 'code': _code.text});
      if (!mounted) return;
      final next = _next;
      final target = next == null ? null : _page.resolve(next);
      if (target != null && !(target.path == widget.client.base.path && target.query.isEmpty)) {
        await _navigate(target);
      } else {
        widget.onSignedIn();
      }
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() => _error = refused.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _provider(String name) =>
    _navigate(widget.client.signIn(name, {'next': _next ?? widget.client.base.path}));

  void _otherEmail() => setState(() {
    _sentTo = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: brand.muted);
    return Scaffold(
      backgroundColor: brand.paper,
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: RelayMark(size: 56)),
          const SizedBox(height: 18),
          Semantics(header: true, child: Text('Relay Everything', textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
          const SizedBox(height: 6),
          ...switch (_load) {
            _Load.loading => [
              Text('Loading…', textAlign: TextAlign.center, style: muted),
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            _Load.access => [
              Text('Sign in to see Relay Everything. Reload this page to sign in again.', textAlign: TextAlign.center,
                style: muted),
            ],
            _Load.failed => [
              Text(noAnswer, textAlign: TextAlign.center, style: muted),
              const SizedBox(height: 16),
              Center(child: OutlinedButton(onPressed: _read, child: const Text('Try again'))),
            ],
            _Load.ready => _ready(context),
          },
        ]),
      )))),
    );
  }

  List<Widget> _ready(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: brand.muted);
    final small = text.bodySmall?.copyWith(color: brand.muted);
    final methods = _methods;
    final others = methods.apple || methods.google;
    Widget alert(String words) => Padding(padding: const EdgeInsets.only(top: 12),
      child: Semantics(liveRegion: true, child: Text(words, style: text.bodyMedium?.copyWith(color: brand.danger))));
    return [
      Text('Sign in or make an account', textAlign: TextAlign.center, style: muted),
      if (_failed) alert('That sign-in did not work. Try again.'),
      const SizedBox(height: 24),
      if (methods.email) ...(_sentTo == null ? _emailForm(context) : _codeForm(context, _sentTo!)),
      if (_error case final error?) alert(error),
      if (methods.email && others) ...[
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: Divider(color: brand.line)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: muted)),
          Expanded(child: Divider(color: brand.line)),
        ]),
        const SizedBox(height: 18),
      ],
      if (methods.apple)
        OutlinedButton.icon(onPressed: () => _provider('apple'), icon: const Icon(CupertinoIcons.person_crop_circle),
          label: const Text('Sign in with Apple')),
      if (methods.apple && methods.google) const SizedBox(height: 10),
      if (methods.google)
        OutlinedButton.icon(onPressed: () => _provider('google'), icon: const Icon(CupertinoIcons.globe),
          label: const Text('Sign in with Google')),
      if (methods.signUp) ...[
        const SizedBox(height: 20),
        Text('New here? The same steps make your account.', textAlign: TextAlign.center, style: small),
      ],
      if (methods.contact case final contact?) ...[
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Questions or privacy requests: ', style: small),
          InkWell(
            onTap: () => _navigate(Uri(scheme: 'mailto', path: contact)),
            child: Semantics(link: true, child: Text(contact,
              style: small?.copyWith(color: brand.accentText, decoration: TextDecoration.underline))),
          ),
        ]),
      ],
    ];
  }

  List<Widget> _emailForm(BuildContext context) => [
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.go,
      decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
      onSubmitted: (_) => _sendCode(),
    ),
    const SizedBox(height: 12),
    FilledButton(onPressed: _email.text.trim().isEmpty || _busy ? null : _sendCode, child: const Text('Email me a code')),
  ];

  List<Widget> _codeForm(BuildContext context, String email) {
    final text = Theme.of(context).textTheme;
    return [
      Text.rich(TextSpan(children: [
        const TextSpan(text: 'We sent a code to '),
        TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(text: '. It works for 10 minutes.'),
      ]), style: text.bodyMedium),
      const SizedBox(height: 12),
      TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        textInputAction: TextInputAction.go,
        decoration: const InputDecoration(labelText: 'Code'),
        onSubmitted: (_) => _signIn(),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _code.text.length != 6 || _busy ? null : _signIn, child: const Text('Sign in')),
      const SizedBox(height: 4),
      TextButton(onPressed: _busy ? null : _otherEmail, child: const Text('Use another email')),
    ];
  }
}
