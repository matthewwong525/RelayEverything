import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditorState;

import '../brand.dart';
import '../relay.dart';
import 'back_to.dart';
import 'folder.dart' show Opener, askAlert;
import 'more_menu.dart';
import 'note_editor.dart' show FilesPicker, Sharer;
import 'round_button.dart' show RoundIconButton;
import 'timeline.dart';

/// What *Recently Deleted* says under its title.
const keepLine = 'Notes are available here for 30 days. After that time, notes will be permanently deleted.';

/// *Recently Deleted*, as in Apple Notes: the notes deleted in the last 30 days, by the day each was deleted. A swipe to
/// the left shows *Recover* and *Delete*, and ⋯ has *Recover All* and *Delete All*. It has no *New note*. A note opens
/// to read only.
class RecentlyDeletedScreen extends StatelessWidget {
  const RecentlyDeletedScreen({super.key, required this.relay, this.picker, this.sharer, this.opener, this.onOpen,
    this.onBack, this.selected});

  final Relay relay;
  final FilesPicker? picker;
  final Sharer? sharer;
  final Opener? opener;
  /// In the browser's wide layout, a note opens beside the list.
  final NoteOpener? onOpen;
  /// Goes back where the browser's layout holds the page.
  final VoidCallback? onBack;
  /// The note open beside the list.
  final String? selected;

  static const title = 'Recently Deleted';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) {
          final notes = relay.deleted;
          final muted = TextStyle(fontSize: 14, height: 1.4, color: brandOf(context).muted);
          return CustomScrollView(slivers: [
            TitleBar(
              title: title,
              relay: relay,
              // Empty, the page says *No notes* once, in its middle, as Apple Notes does.
              count: notes.isEmpty ? null : countOf(notes.length),
              leading: BackTo('Home', onPressed: onBack),
              leadingWidth: BackTo.widthOf('Home'),
              actions: [
                if (notes.isNotEmpty) MoreMenu(
                  items: [('Recover All', CupertinoIcons.arrow_uturn_left, () => unawaited(relay.recoverAll()))],
                  destructive: ('Delete All', CupertinoIcons.trash, () => unawaited(deleteAll(context, relay))),
                  builder: (context, toggle) => RoundIconButton(icon: CupertinoIcons.ellipsis, tooltip: 'More', onPressed: toggle),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 4), child: Text(keepLine, style: muted))),
            if (notes.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: Padding(padding: const EdgeInsets.all(32),
                child: Text('No notes', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: brandOf(context).muted)))))
            else
              noteSliver(context, relay, notes, '', back: title, picker: picker, sharer: sharer, opener: opener,
                onOpen: onOpen, selected: selected, deleted: true),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ]);
        },
      ),
    );
  }
}

/// Asks first, as it can't be undone, then deletes every note in *Recently Deleted* for good.
Future<void> deleteAll(BuildContext context, Relay relay) async {
  final count = relay.deleted.length;
  if (count == 0) return;
  if (!await askAlert(context, title: count == 1 ? 'Delete 1 note?' : 'Delete $count notes?',
    message: "These notes will be deleted for good. You can't undo this.", action: 'Delete All', destructive: true)) {
    return;
  }
  await relay.deleteAll();
}

/// The iPhone's shake: the runner calls `shake` on it when the person shakes the phone.
const shakeChannel = MethodChannel('relay/shake');

/// True while words are being typed: a text field or a note's words have the focus. A shake or ⌘Z then undoes the
/// typing, as it always did, not a delete.
bool textHasFocus() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return focused.widget is EditableText || focused.findAncestorStateOfType<EditableTextState>() != null ||
    focused.findAncestorStateOfType<QuillEditorState>() != null;
}

/// After a shake: *Undo Delete Note*, with *Cancel* and *Undo*, when a delete can be undone and no words are being
/// typed; else nothing. *Undo* brings the last deleted note back.
Future<void> askUndoDelete(BuildContext context, Relay relay) async {
  if (!relay.canUndoDelete || textHasFocus()) return;
  if (await askAlert(context, title: 'Undo Delete Note', action: 'Undo')) await relay.undoLastDelete();
}
