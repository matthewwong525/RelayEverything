import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../screens/connect_ai.dart' show pluginGuide;
import '../screens/days.dart' show daysAgo;
import '../screens/folder.dart' show Opener, openInBrowser;
import '../screens/transcripts.dart' show TranscriptSteps;
import 'space.dart';

// Saved AI chat transcripts from Claude Code and Codex in the browser: search, the list newest first, and one chat with
// the AI's saves above its messages. The Relay Everything plugin sends them with a computer's key;
// app/worker/apps/relay/chat-read.ts answers.

/// One chat in the list: `GET chats`.
class ChatSummary {
  const ChatSummary({required this.id, required this.title, required this.project, required this.startedAt,
    required this.lastAt, required this.messages, required this.savedByAi, this.app = 'claude-code'});

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
    id: json['id'] as String, title: json['title'] as String? ?? '', project: json['project'] as String? ?? '',
    startedAt: _time(json['startedAt']), lastAt: _time(json['lastAt']), messages: (json['messages'] as num?)?.toInt() ?? 0,
    savedByAi: json['savedByAi'] == true, app: json['app'] as String? ?? 'claude-code');

  final String id;
  final String title;
  final String project;
  final DateTime startedAt;
  final DateTime lastAt;
  final int messages;
  final bool savedByAi;
  /// The app the chat came from, as the server names it: `claude-code` or `codex`. An older chat has none, and came
  /// from Claude Code.
  final String app;

  /// The app's name to show: *Codex*, else *Claude Code*.
  String get appName => app == 'codex' ? 'Codex' : 'Claude Code';
}

/// A title and summary the AI saved beside a chat.
class ChatSave {
  const ChatSave({required this.id, required this.title, required this.text, required this.createdAt});

  factory ChatSave.fromJson(Map<String, dynamic> json) => ChatSave(id: json['id'] as String,
    title: json['title'] as String? ?? '', text: json['text'] as String? ?? '', createdAt: _time(json['createdAt']));

  final String id;
  final String title;
  final String text;
  final DateTime createdAt;
}

/// One message: `you`, `ai`, or `step`, one step the AI took.
class ChatMessage {
  const ChatMessage({required this.seq, required this.role, required this.text});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(seq: (json['seq'] as num).toInt(),
    role: json['role'] as String? ?? 'step', text: json['text'] as String? ?? '');

  final int seq;
  final String role;
  final String text;
}

DateTime _time(Object? ms) => DateTime.fromMillisecondsSinceEpoch((ms as num?)?.toInt() ?? 0);

List<Map<String, dynamic>> _list(Object? value) =>
  value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

/// A page of the list, with where the next page starts.
class _ChatList {
  _ChatList(Map<String, dynamic> json)
    : chats = _list(json['chats']).map(ChatSummary.fromJson).toList(),
      next = (json['next'] as num?)?.toInt(), nextId = json['nextId'] as String?;

  final List<ChatSummary> chats;
  final int? next;
  final String? nextId;
}

String _plural(int count, String word) => '$count $word${count == 1 ? '' : 's'}';

/// A time as the page shows it: the clock alone today, with the date on another day.
String _when(BuildContext context, DateTime at) {
  final time = TimeOfDay.fromDateTime(at).format(context);
  if (daysAgo(at, DateTime.now()) == 0) return time;
  return '${MaterialLocalizations.of(context).formatShortMonthDay(at)}, $time';
}

/// The saved AI chat transcripts. [wide] shows the list in a middle pane and the open chat to its right; else a tap
/// opens the chat as its own page. [opener] opens the website's guide; a test passes its own.
class ChatsView extends StatefulWidget {
  const ChatsView({super.key, required this.client, required this.wide, this.opener});

  final SpaceClient client;
  final bool wide;
  final Opener? opener;

  @override
  State<ChatsView> createState() => _ChatsViewState();
}

class _ChatsViewState extends State<ChatsView> {
  final _search = TextEditingController();
  String _query = '';
  List<_ChatList>? _pages;
  bool _failed = false;
  bool _olderFailed = false;
  bool _loadingOlder = false;
  String? _opened;
  /// Counts reads, so an answer for an earlier search does not replace a newer one.
  int _round = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final round = ++_round;
    setState(() {
      _pages = null;
      _failed = false;
      _olderFailed = false;
    });
    try {
      final json = await widget.client.get('chats', query: _query.isEmpty ? null : {'q': _query});
      if (!mounted || round != _round) return;
      setState(() => _pages = [_ChatList(json)]);
    } on SpaceRefused {
      if (mounted && round == _round) setState(() => _failed = true);
    }
  }

  Future<void> _older() async {
    final pages = _pages;
    if (pages == null || _loadingOlder) return;
    final last = pages.last;
    if (last.next == null) return;
    final round = _round;
    setState(() => _loadingOlder = true);
    try {
      final json = await widget.client.get('chats', query: {
        if (_query.isNotEmpty) 'q': _query,
        'before': '${last.next}',
        if (last.nextId != null) 'beforeId': last.nextId!,
      });
      if (!mounted || round != _round) return;
      setState(() {
        _pages = [...pages, _ChatList(json)];
        _olderFailed = false;
      });
    } on SpaceRefused {
      if (mounted && round == _round) setState(() => _olderFailed = true);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _find(String typed) {
    final query = typed.trim();
    if (query == _query && _pages != null) return;
    _query = query;
    _read();
  }

  Future<void> _open(ChatSummary chat) async {
    if (widget.wide) {
      setState(() => _opened = chat.id);
      return;
    }
    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Saved chats')),
      body: _ChatPane(key: ValueKey(chat.id), client: widget.client, id: chat.id,
        onDeleted: () => Navigator.of(context).pop(true)),
    )));
    if (deleted == true && mounted) _read();
  }

  void _deleted() {
    setState(() => _opened = null);
    _read();
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final list = _listPane(context);
    if (!widget.wide) return Material(color: brand.paper, child: list);
    final opened = _opened;
    return Material(color: brand.paper, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 360, child: list),
      VerticalDivider(width: 1, color: brand.line),
      Expanded(child: opened == null
        ? Center(child: Text('Pick a chat to read it.', style: TextStyle(color: brand.muted)))
        : _ChatPane(key: ValueKey(opened), client: widget.client, id: opened, onDeleted: _deleted)),
    ]));
  }

  Widget _listPane(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 14, 12, 6), child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text('Saved chats',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)))),
        TextButton(onPressed: () => showDialog<void>(context: context,
          builder: (_) => _ConnectComputer(opener: widget.opener ?? openInBrowser)), child: const Text('Connect a computer')),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(hintText: 'Search your chats', prefixIcon: Icon(CupertinoIcons.search),
          isDense: true),
        onSubmitted: _find,
        onChanged: (typed) {
          if (typed.trim().isEmpty && _query.isNotEmpty) _find('');
        },
      )),
      Expanded(child: _listBody(context, brand)),
    ]);
  }

  Widget _listBody(BuildContext context, BrandColors brand) {
    final text = Theme.of(context).textTheme;
    if (_failed) return _Failed(what: 'Chats', retry: _read);
    final pages = _pages;
    if (pages == null) return const Center(child: CircularProgressIndicator());
    final chats = [for (final page in pages) ...page.chats];
    if (chats.isEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: Text(_query.isEmpty
        ? 'No chats yet. Connect a computer from Claude Code or Codex, and each chat from then on is saved here.'
        : 'No chat holds those words.', style: text.bodyMedium?.copyWith(color: brand.muted)));
    }
    final more = pages.last.next != null;
    return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 24), children: [
      for (final chat in chats) _Row(chat: chat, on: widget.wide && chat.id == _opened, open: () => _open(chat)),
      if (_olderFailed)
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: Semantics(liveRegion: true,
          child: Text('Older chats could not be loaded.', style: text.bodyMedium?.copyWith(color: brand.danger)))),
      if (more)
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: Align(alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _loadingOlder ? null : _older, child: const Text('Show older chats')))),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.chat, required this.on, required this.open});

  final ChatSummary chat;
  final bool on;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Material(
      color: on ? brand.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: open,
        child: Semantics(button: true, selected: on, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(chat.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
              if (chat.savedByAi) ...[const SizedBox(width: 8), const BrandTag('Saved by the AI')],
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(child: Text([chat.project, _when(context, chat.lastAt), _plural(chat.messages, 'message')].join(' · '),
                style: text.bodySmall?.copyWith(color: brand.muted))),
              const SizedBox(width: 8),
              BrandTag(chat.appName, outlined: true),
            ]),
          ]),
        )),
      ),
    ));
  }
}

/// One chat: its title with *Delete*, the AI's saves, then each message, the AI's steps as muted single lines.
class _ChatPane extends StatefulWidget {
  const _ChatPane({super.key, required this.client, required this.id, required this.onDeleted});

  final SpaceClient client;
  final String id;
  final VoidCallback onDeleted;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  ChatSummary? _chat;
  List<ChatSave> _saves = const [];
  final _messages = <ChatMessage>[];
  int? _next;
  bool _failed = false;
  bool _moreFailed = false;
  bool _loadingMore = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _chat = null;
      _failed = false;
    });
    try {
      final json = await widget.client.get('chat', query: {'id': widget.id});
      if (!mounted) return;
      setState(() {
        _chat = ChatSummary.fromJson(json['chat'] as Map<String, dynamic>);
        _saves = _list(json['saves']).map(ChatSave.fromJson).toList();
        _messages..clear()..addAll(_list(json['messages']).map(ChatMessage.fromJson));
        _next = (json['next'] as num?)?.toInt();
      });
    } on SpaceRefused {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _more() async {
    final next = _next;
    if (next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final json = await widget.client.get('chat', query: {'id': widget.id, 'after': '$next'});
      if (!mounted) return;
      setState(() {
        _messages.addAll(_list(json['messages']).map(ChatMessage.fromJson));
        _next = (json['next'] as num?)?.toInt();
        _moreFailed = false;
      });
    } on SpaceRefused {
      if (mounted) setState(() => _moreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _delete() async {
    final chat = _chat;
    if (chat == null) return;
    setState(() => _error = null);
    final yes = await showDialog<bool>(context: context, builder: (context) {
      final brand = brandOf(context);
      return AlertDialog(
        title: Text('Delete ${chat.title}?'),
        content: const Text("Relay Everything removes the chat, its messages and the AI's summary. You can't undo it."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: brand.danger), child: const Text('Delete')),
        ],
      );
    });
    if (yes != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.client.delete('chat', query: {'id': widget.id});
      if (mounted) widget.onDeleted();
    } on SpaceRefused {
      if (mounted) setState(() => _error = 'The chat could not be deleted. Try again.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _Failed(what: 'The chat', retry: _read);
    final chat = _chat;
    if (chat == null) return const Center(child: CircularProgressIndicator());
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: brand.muted);
    return SelectionArea(child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 32), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Semantics(header: true, child: Text(chat.title,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)))),
        const SizedBox(width: 8),
        TextButton(onPressed: _deleting ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: brand.danger), child: const Text('Delete')),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text([chat.project, _when(context, chat.startedAt)].join(' · '), style: muted),
        BrandTag(chat.appName, outlined: true),
      ]),
      if (_error case final error?)
        Padding(padding: const EdgeInsets.only(top: 8), child: Semantics(liveRegion: true,
          child: Text(error, style: text.bodyMedium?.copyWith(color: brand.danger)))),
      for (final save in _saves) Padding(padding: const EdgeInsets.only(top: 16), child: Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: brand.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: brand.line, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const BrandTag('Written by the AI'),
              Text('${save.title} · ${_when(context, save.createdAt)}', style: muted),
            ]),
            const SizedBox(height: 8),
            Text(save.text, style: text.bodyMedium),
          ]),
        ),
      )),
      for (final message in _messages) _Message(message: message),
      if (_moreFailed)
        Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true,
          child: Text('More messages could not be loaded.', style: text.bodyMedium?.copyWith(color: brand.danger)))),
      if (_next != null)
        Padding(padding: const EdgeInsets.only(top: 16), child: Align(alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _loadingMore ? null : _more, child: const Text('Show more messages')))),
    ]));
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: brand.muted);
    if (message.role == 'step') {
      return Padding(padding: const EdgeInsets.only(top: 8), child: Text(message.text, style: muted));
    }
    return Padding(padding: const EdgeInsets.only(top: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message.role == 'ai' ? 'AI' : 'You', style: muted),
        const SizedBox(height: 2),
        Text(message.text, style: text.bodyMedium),
      ]));
  }
}

/// A part that could not be read, with a button to read it again.
class _Failed extends StatelessWidget {
  const _Failed({required this.what, required this.retry});

  final String what;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Padding(padding: const EdgeInsets.all(20), child: Wrap(spacing: 12, runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center, children: [
        Semantics(liveRegion: true, child: Text('$what could not be loaded.', style: TextStyle(color: brand.danger))),
        OutlinedButton(onPressed: retry, child: const Text('Try again')),
      ]));
  }
}

/// How to save a computer's AI chats here: the plugin in Claude Code or Codex, then `/relay:connect`.
class _ConnectComputer extends StatelessWidget {
  const _ConnectComputer({required this.opener});

  final Opener opener;

  static final guide = Uri.parse(pluginGuide);

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: brand.muted);
    return AlertDialog(
      title: const Text('Connect a computer'),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The Relay Everything plugin saves your Claude Code and Codex chats word for word. Do these steps one time '
            'on each computer.', style: text.bodyMedium),
          const TranscriptSteps(),
          const SizedBox(height: 16),
          Text('Each chat from then on is saved. Older chats are not sent. To keep the chats of a project out, type '
            '/relay:saving off in that project.', style: muted),
          const SizedBox(height: 8),
          Text("The computer's key saves your chats and can read all your Relay Everything data. To stop it, disconnect "
            'it in Connect your AI.', style: muted),
          const SizedBox(height: 8),
          Text('To keep chats in your own Cloudflare account, run your own Relay Everything server and connect to it.',
            style: muted),
        ]),
      )),
      actions: [
        TextButton(onPressed: () => unawaited(opener(guide)), child: const Text('Read the guide')),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
