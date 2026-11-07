import 'dart:async';

import 'package:flutter/material.dart';

import '../data/attachments.dart';
import 'draft.dart';

/// What *Save* did with a share.
enum ShareOutcome {
  /// The note and its files are in the person's space.
  sent,
  /// Sending is off, or the phone has no key: the note stays on this phone.
  kept,
  /// Sending is on, but the note did not all go in time, such as with no signal: the app sends the rest later.
  later,
}

/// The card's foot line for each state. The iPhone's card (`ios/ShareExtension/ShareViewController.swift`) says the
/// same words.
const sendingOn = 'Sending is on: this goes to your space.';
const sendingOff = 'Kept on this phone. Sending is off.';
const sendingNow = 'Sending…';
const sentNow = 'Sent';
const sendsLater = 'Kept. It sends when you open Relay Everything.';

/// The share card over the app the person shares from: what they share, *Add words*, and *Save*. It closes after
/// *Save* or *Cancel*, and the person is back where they were.
class ShareCard extends StatefulWidget {
  const ShareCard({super.key, required this.draft, required this.sending, required this.save, required this.close,
    this.linger = const Duration(milliseconds: 900)});

  final ShareDraft draft;
  /// True while sending is on and the phone has a key.
  final bool sending;
  /// Keeps the note with the person's words, and sends it while sending is on.
  final Future<ShareOutcome> Function(String words) save;
  /// Closes the card, back to the other app.
  final VoidCallback close;
  /// How long the last line stays before the card closes.
  final Duration linger;

  @override
  State<ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends State<ShareCard> {
  final _words = TextEditingController();
  bool _saving = false;
  String? _foot;

  @override
  void initState() {
    super.initState();
    _words.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _foot = widget.sending ? sendingNow : null;
    });
    ShareOutcome outcome;
    try {
      outcome = await widget.save(_words.text);
    } on Exception {
      outcome = widget.sending ? ShareOutcome.later : ShareOutcome.kept;
    }
    if (!mounted) return;
    setState(() => _foot = switch (outcome) { ShareOutcome.sent => sentNow, ShareOutcome.kept => sendingOff, ShareOutcome.later => sendsLater });
    await Future<void>.delayed(widget.linger);
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final canSave = !_saving && draft.canSave(_words.text);
    return Scaffold(
      backgroundColor: Colors.black38,
      body: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  TextButton(onPressed: _saving ? null : widget.close, child: const Text('Cancel')),
                  Expanded(child: Text('Relay Everything', textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
                  FilledButton(onPressed: canSave ? _save : null, child: const Text('Save')),
                ]),
                const SizedBox(height: 12),
                if (draft.title != null || draft.url != null)
                  _Shared(children: [
                    if (draft.title != null) Text(draft.title!, style: theme.textTheme.bodyLarge),
                    if (draft.url != null) Text(draft.url!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                if (draft.text != null)
                  _Shared(children: [Text(draft.text!, maxLines: 4, overflow: TextOverflow.ellipsis)]),
                if (draft.files.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final file in draft.files)
                        Chip(label: Text('${file.name} · ${sizeLabel(file.size)}'), visualDensity: VisualDensity.compact),
                    ]),
                  ),
                TextField(controller: _words, enabled: !_saving, minLines: 1, maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Add words', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                if (draft.leftOut != null)
                  Text(draft.leftOut!, style: TextStyle(color: theme.colorScheme.error)),
                Text(_foot ?? (widget.sending ? sendingOn : sendingOff), style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Shared extends StatelessWidget {
  const _Shared({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}
