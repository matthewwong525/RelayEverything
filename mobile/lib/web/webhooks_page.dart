import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import 'settings_parts.dart';
import 'space.dart';

/// One kind of data a webhook can take, as `GET webhooks` lists it: notes always go; the rest each have a tick.
class WebhookKind {
  WebhookKind.fromJson(Map<String, dynamic> json)
    : id = '${json['id']}', label = '${json['label'] ?? json['id']}', detail = '${json['detail'] ?? ''}',
      always = json['always'] == true, sensitive = json['sensitive'] == true;

  final String id;
  final String label;
  final String detail;
  final bool always;
  final bool sensitive;
}

const _states = {'working': 'Working', 'paused': 'Paused', 'failing': 'Failing', 'backfilling': 'Sending past data'};

String _duration(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';

/// The card's line: what waits, when the next try is, and the last answer.
String webhookLine(Map<String, dynamic> hook) {
  int? ms(String key) => hook[key] is int ? hook[key] as int : null;
  final waiting = ms('waiting') ?? 0;
  final answer = hook['lastError'] ?? (hook['lastStatus'] == null ? null : 'answered ${hook['lastStatus']}');
  final parts = [
    if (waiting > 0) '$waiting waiting',
    if (ms('nextTryAt') case final at?) 'next try ${whenOf(at)}',
    if (ms('failingSince') case final at?) 'failing since ${whenOf(at)}',
    if (ms('lastSentAt') case final at?) 'last sent ${whenOf(at)}',
    if (answer != null) 'last answer: $answer',
  ];
  return parts.isEmpty ? 'nothing sent yet' : parts.join(' · ');
}

/// What a test got back, as one sentence.
String testLine(Map<String, dynamic> answer) {
  final error = answer['error'];
  if (answer['status'] == null) return 'No answer: $error';
  return 'Answered ${answer['status']} in ${_duration(answer['ms'] is int ? answer['ms'] as int : 0)}.'
    '${error == null ? '' : ' $error'}';
}

/// *A is*, or *A, B and C are*.
String _listed(List<String> words) =>
  words.length < 2 ? '${words.join()} is' : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last} are';

/// *Webhooks*: where Relay Everything sends the person's data, each with its state and actions, and *Add a webhook*.
/// The server lists the kinds, so a new kind gets its tick and name here by itself.
class WebhooksPage extends StatelessWidget {
  const WebhooksPage({super.key, required this.client});

  final SpaceClient client;

  Future<(List<Map<String, dynamic>>, List<WebhookKind>)> _load() async {
    final json = await client.get('webhooks');
    return (listOf(json, 'webhooks'), [for (final kind in listOf(json, 'kinds')) WebhookKind.fromJson(kind)]);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'Webhooks', line: 'Relay Everything sends each new note to your own database, signed.',
      children: [SpaceView<(List<Map<String, dynamic>>, List<WebhookKind>)>(what: 'Webhooks', load: _load,
        builder: (context, value, act) {
          final (hooks, kinds) = value;
          final names = {for (final kind in kinds) kind.id: kind.label.toLowerCase()};
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (hooks.isEmpty) const Note('No webhooks yet. Add one to copy each new note to your own database.'),
            for (final hook in hooks)
              _HookCard(key: ValueKey(hook['id']), hook: hook, kinds: kinds, names: names, client: client, changed: act),
            // An older server lists no kinds, so it offers no form.
            if (kinds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () async {
                  final added = await showDialog<bool>(context: context,
                    builder: (_) => AddWebhookDialog(client: client, kinds: kinds));
                  if (added == true) await act();
                },
                icon: const Icon(CupertinoIcons.add), label: const Text('Add a webhook')))),
          ]);
        })]);
  }
}

class _HookCard extends StatefulWidget {
  const _HookCard({super.key, required this.hook, required this.kinds, required this.names, required this.client,
    required this.changed});

  final Map<String, dynamic> hook;
  final List<WebhookKind> kinds;
  final Map<String, String> names;
  final SpaceClient client;
  final Future<void> Function() changed;

  @override
  State<_HookCard> createState() => _HookCardState();
}

class _HookCardState extends State<_HookCard> {
  String? _message;

  Map<String, dynamic> get hook => widget.hook;
  String get name => '${hook['name']}';

  /// Runs one action; its refusal shows on the card. True when it worked.
  Future<bool> _act(Future<void> Function() work, {bool reload = true}) async {
    try {
      await work();
      if (reload) await widget.changed();
      return true;
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() => _message = refused.message);
      return false;
    }
  }

  Future<void> _post(String route, [Map<String, Object?> more = const {}]) =>
    widget.client.post(route, {'id': hook['id'], ...more});

  Future<void> _test() async {
    setState(() => _message = 'Sending a test…');
    await _act(reload: false, () async {
      final answer = await widget.client.post('webhooks/test', {'id': hook['id']});
      if (mounted) setState(() => _message = testLine(answer));
    });
  }

  Future<void> _sendPast() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: now.subtract(const Duration(days: 7)),
      firstDate: DateTime(2020), lastDate: now, helpText: 'Send past data from', confirmText: 'Send');
    if (day == null) return;
    await _act(() => _post('webhooks/resend', {'since': DateTime(day.year, day.month, day.day).millisecondsSinceEpoch}));
  }

  Future<void> _newSecret() async {
    if (!await confirm(context, title: 'Make a new secret for $name?', action: 'New secret',
      body: 'The old secret stops working at once. Put the new one in your database before the next message.')) {
      return;
    }
    await _act(reload: false, () async {
      final secret = '${(await widget.client.post('webhooks/secret', {'id': hook['id']}))['secret']}';
      if (mounted) await showDialog<void>(context: context, builder: (_) => _SecretDialog(title: 'New secret', secret: secret));
    });
  }

  Future<void> _remove() async {
    if (!await confirm(context, title: 'Remove $name?', action: 'Remove',
      body: 'Relay Everything stops sending to it and deletes its secret and send history. You can not undo this. '
        'Your notes stay in Relay Everything.')) {
      return;
    }
    await _act(() => _post('webhooks/remove'));
  }

  Future<void> _editKinds() async {
    final changed = await showDialog<bool>(context: context,
      builder: (_) => _KindsDialog(client: widget.client, kinds: widget.kinds, hook: hook));
    if (changed == true) await widget.changed();
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final state = '${hook['state']}';
    final paused = state == 'paused';
    final kinds = [for (final kind in hook['kinds'] is List ? hook['kinds'] as List : const []) widget.names[kind] ?? '$kind'];
    final host = Uri.tryParse('${hook['url']}')?.host ?? '';
    Widget button(String label, VoidCallback onPressed) =>
      TextButton(onPressed: onPressed, style: quietButton(context), child: Text(label));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(child: Semantics(label: name, container: true, child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Text(_states[state] ?? state, style: TextStyle(fontWeight: FontWeight.w600,
              color: state == 'failing' ? brand.danger : paused ? brand.muted : brand.accentText)),
          ]),
          Text('$host · ${kinds.join(', ')} · ${webhookLine(hook)}', style: TextStyle(color: brand.muted)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            button('Send a test', _test),
            if (state == 'failing') button('Try again now', () => _act(() => _post('webhooks/retry')))
            else button('Send past data', _sendPast),
            if (widget.kinds.isNotEmpty) button('What it takes', _editKinds),
            button('New secret', _newSecret),
            button(paused ? 'Resume' : 'Pause', () => _act(() => _post('webhooks/update', {'active': paused}))),
            button('Remove', _remove),
          ]),
          if (_message case final message?) Semantics(liveRegion: true, child: Text(message)),
        ]),
      ))),
    );
  }
}

/// The ticks for each kind that is not always sent, with the sensitive kinds named under them.
class _Ticks extends StatelessWidget {
  const _Ticks({required this.kinds, required this.ticked, required this.onTick});

  final List<WebhookKind> kinds;
  final Set<String> ticked;
  final void Function(String id, bool on) onTick;

  @override
  Widget build(BuildContext context) {
    final sensitive = [for (final (index, kind) in kinds.where((kind) => kind.sensitive).indexed)
      index == 0 ? kind.label : kind.label.toLowerCase()];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final kind in kinds.where((kind) => kind.always))
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${kind.label} always go, ${kind.detail}.')),
      for (final kind in kinds.where((kind) => !kind.always))
        CheckboxListTile(
          contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, dense: true,
          value: ticked.contains(kind.id), onChanged: (on) => onTick(kind.id, on == true),
          title: Text(kind.detail.isEmpty ? kind.label : '${kind.label}: ${kind.detail}')),
      if (sensitive.isNotEmpty) Note('${_listed(sensitive)} sensitive. Tick each only for a database you control.'),
    ]);
  }
}

/// *Add a webhook*: a name, an address and the kinds, then its secret, shown once. Closes with true once one was added.
class AddWebhookDialog extends StatefulWidget {
  const AddWebhookDialog({super.key, required this.client, required this.kinds});

  final SpaceClient client;
  final List<WebhookKind> kinds;

  @override
  State<AddWebhookDialog> createState() => _AddWebhookDialogState();
}

class _AddWebhookDialogState extends State<AddWebhookDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController(text: 'https://');
  final _ticked = <String>{};
  String? _secret;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() => _problem = null);
    try {
      final made = await widget.client.post('webhooks', {
        'name': _name.text.trim().isEmpty ? 'My database' : _name.text.trim(),
        'url': _url.text.trim(),
        'kinds': [for (final kind in widget.kinds) if (_ticked.contains(kind.id)) kind.id],
      });
      if (mounted) setState(() => _secret = '${made['secret']}');
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() => _problem = refused.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secret = _secret;
    if (secret != null) return _SecretDialog(title: 'Webhook added', secret: secret, result: true);
    return AlertDialog(
      title: const Text('Add a webhook'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 12, children: [
          const Text('Relay Everything sends each new note to this address, signed, a few seconds after it gets it.'),
          TextField(controller: _name,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'My Postgres', border: OutlineInputBorder())),
          TextField(controller: _url, keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
          _Ticks(kinds: widget.kinds, ticked: _ticked,
            onTick: (id, on) => setState(() => on ? _ticked.add(id) : _ticked.remove(id))),
          if (_problem case final problem?) Problem(problem),
        ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _add, child: const Text('Add')),
      ],
    );
  }
}

/// *What it takes*: the ticks for one webhook, saved with `webhooks/update`. Closes with true once saved.
class _KindsDialog extends StatefulWidget {
  const _KindsDialog({required this.client, required this.kinds, required this.hook});

  final SpaceClient client;
  final List<WebhookKind> kinds;
  final Map<String, dynamic> hook;

  @override
  State<_KindsDialog> createState() => _KindsDialogState();
}

class _KindsDialogState extends State<_KindsDialog> {
  late final _ticked = {for (final kind in widget.hook['kinds'] is List ? widget.hook['kinds'] as List : const []) '$kind'};
  String? _problem;

  Future<void> _save() async {
    try {
      await widget.client.post('webhooks/update', {'id': widget.hook['id'],
        'kinds': [for (final kind in widget.kinds) if (!kind.always && _ticked.contains(kind.id)) kind.id]});
      if (mounted) Navigator.pop(context, true);
    } on SpaceRefused catch (refused) {
      if (mounted) setState(() => _problem = refused.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('What ${widget.hook['name']} takes'),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      _Ticks(kinds: widget.kinds, ticked: _ticked, onTick: (id, on) => setState(() => on ? _ticked.add(id) : _ticked.remove(id))),
      if (_problem case final problem?) Problem(problem),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

/// A webhook's secret, shown once to copy. Closes with [result].
class _SecretDialog extends StatelessWidget {
  const _SecretDialog({required this.title, required this.secret, this.result});

  final String title;
  final String secret;
  final bool? result;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(width: 460, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Copy this secret now. Relay Everything shows it once.'),
        CopyField(text: secret, label: 'The secret', button: 'Copy the secret'),
        const Note("Your database uses it to check each message came from Relay Everything. Lost it? Make a new one from "
          "the webhook's card."),
      ])),
    actions: [FilledButton(onPressed: () => Navigator.pop(context, result), child: const Text('Done'))],
  );
}
