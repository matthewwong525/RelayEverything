import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import 'space.dart';

/// The website's page on the web API, for an API key and the AI connector.
const apiDocs = 'https://relayeverything.com/api/connect-a-service/';
/// The website's page on how to install the phone app.
const installPage = 'https://relayeverything.com/start/install/';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A server time in ms as the Settings pages show it: *14:05* today, *Nov 4, 14:05* this year, else with the year.
String whenOf(int ms, [DateTime? now]) {
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = now ?? DateTime.now();
  final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  if (at.year == today.year && at.month == today.month && at.day == today.day) return time;
  final day = '${_months[at.month - 1]} ${at.day}';
  return at.year == today.year ? '$day, $time' : '$day ${at.year}, $time';
}

/// *1,234*: a count with its thousands marked.
String thousands(int count) =>
  count.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// One Settings page: its title, a short line under it, and its parts, as wide as reads well. With [back], a page
/// opened from Account, such as *Webhooks*, starts with *‹ Account*.
class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key, required this.title, this.line, this.back, required this.children});

  final String title;
  final String? line;
  final VoidCallback? back;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Align(alignment: Alignment.topLeft, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(padding: const EdgeInsets.fromLTRB(28, 22, 28, 28), children: [
        if (back case final back?) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: back, style: quietButton(context),
          icon: const Icon(CupertinoIcons.chevron_back, size: 18), label: const Text('Account'))),
        // The dialog's close button sits at the top right, so the title leaves it room.
        Padding(padding: const EdgeInsets.only(right: 48),
          child: Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        if (line case final line?) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(line, style: text.bodyLarge?.copyWith(color: brandOf(context).muted))),
        const SizedBox(height: 8),
        ...children,
      ]),
    ));
  }
}

/// The words of a refusal, in the danger color, read out when they show.
class Problem extends StatelessWidget {
  const Problem(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(liveRegion: true, child: Text(message, style: TextStyle(color: brandOf(context).danger))),
  );
}

/// Smaller, muted words under a part.
class Note extends StatelessWidget {
  const Note(this.words, {super.key});

  final String words;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(words, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: brandOf(context).muted)),
  );
}

/// Runs a change, then reads the page again; a refusal shows under the page, and the page stays as it was. With no
/// change it only reads again.
typedef Act = Future<void> Function([Future<Object?> Function()? change]);

/// Reads one route of the person's space, then shows it: a spinner first, the refusal with *Try again*, or [builder]
/// with its [Act]. [refused] may show its own words for a refusal, such as a 503.
class SpaceView<T> extends StatefulWidget {
  const SpaceView({super.key, required this.what, required this.load, required this.builder, this.refused});

  /// What it reads, for *Devices could not be loaded.*
  final String what;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, Act act) builder;
  final Widget? Function(SpaceRefused refused)? refused;

  @override
  State<SpaceView<T>> createState() => _SpaceViewState<T>();
}

class _SpaceViewState<T> extends State<SpaceView<T>> {
  T? _value;
  bool _loaded = false;
  SpaceRefused? _problem;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final value = await widget.load();
      if (mounted) setState(() { _value = value; _loaded = true; _problem = null; });
    } catch (error) {
      // An answer of the wrong shape reads as no answer.
      if (mounted) setState(() => _problem = error is SpaceRefused ? error : const SpaceRefused(null, noAnswer));
    }
  }

  Future<void> _act([Future<Object?> Function()? change]) async {
    if (change != null) {
      try {
        await change();
      } on SpaceRefused catch (refused) {
        if (mounted) setState(() => _problem = refused);
        return;
      }
    }
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    if (!_loaded && problem != null) {
      return widget.refused?.call(problem) ?? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Problem('${widget.what} could not be loaded. ${problem.message}'),
        TextButton(onPressed: () { setState(() => _problem = null); _read(); }, style: quietButton(context),
          child: const Text('Try again')),
      ]);
    }
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      widget.builder(context, _value as T, _act),
      if (problem != null) Problem(problem.message),
    ]);
  }
}

/// Text to copy, such as a key or an address: shown in full and selectable, with a *Copy* button that says when it
/// copied. [label] names the text for a screen reader and a test.
class CopyField extends StatefulWidget {
  const CopyField({super.key, required this.text, required this.label, this.button = 'Copy'});

  final String text;
  final String label;
  final String button;

  @override
  State<CopyField> createState() => _CopyFieldState();
}

class _CopyFieldState extends State<CopyField> {
  String? _said;

  Future<void> _copy() async {
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } on Exception {
      copied = false;
    }
    if (mounted) setState(() => _said = copied ? 'Copied' : 'Copy did not work. Select the text and copy it.');
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: brand.card, border: Border.all(color: brand.line),
            borderRadius: BorderRadius.circular(12)),
          child: Semantics(label: widget.label, child: SelectableText(widget.text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
        ),
        Row(spacing: 8, children: [
          FilledButton.icon(onPressed: _copy, icon: Icon(_said == 'Copied' ? CupertinoIcons.checkmark : CupertinoIcons.doc_on_doc,
            size: 18), label: Text(widget.button)),
          if (_said case final said?) Flexible(child: Text(said, style: TextStyle(color: brand.muted))),
        ]),
      ]),
    );
  }
}

/// Asks before a change that can not be undone: true for [action], false for *Cancel* or a tap outside.
Future<bool> confirm(BuildContext context, {required String title, required String body, required String action}) async =>
  await showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: Text(title),
    content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(body)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
    ],
  )) == true;

/// The list in a route's answer, such as `devices`, with each item that is not an object left out.
List<Map<String, dynamic>> listOf(Map<String, dynamic> json, String key) =>
  [for (final item in json[key] is List ? json[key] as List : const []) if (item is Map<String, dynamic>) item];
