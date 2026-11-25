import 'package:flutter/foundation.dart' show kIsWeb;

import 'host.dart' as host;
import 'web_note.dart';

/// Editor pages made before they are needed, so a note opens at once: a web view takes a moment to start. One page is
/// ready from the app's start and one more waits as the spare; each note takes one, and a new spare starts at once. A
/// note's page is never used again for another note: it is let go when the note closes. [warm] starts them, once the
/// app runs.
class WebNotePool {
  WebNotePool(this.make, {this.spares = 2});

  /// The app's pool. A test puts one with its own pages here. The browser keeps no spare: a frame loads its page only
  /// once it is on the screen, so a spare would wait unloaded.
  static WebNotePool shared = WebNotePool(host.makeWebNote, spares: kIsWeb ? 0 : 2);

  /// Makes one new page.
  final WebNote Function() make;

  /// How many pages wait for a note.
  final int spares;

  final _waiting = <WebNote>[];

  /// Each page this pool made, newest last: a test reads the page a note took.
  final made = <WebNote>[];

  /// How many pages wait now.
  int get waiting => _waiting.length;

  WebNote _new() {
    final note = make();
    made.add(note);
    return note;
  }

  /// Starts the pages that wait, up to [spares].
  void warm() {
    while (_waiting.length < spares) {
      _waiting.add(_new());
    }
  }

  /// A page for one note: one that waits and has started, else any that waits, else a new one. The pool starts a
  /// new spare in its place.
  WebNote take() {
    final started = _waiting.where((note) => note.booted).firstOrNull ?? _waiting.firstOrNull;
    final note = started ?? _new();
    _waiting.remove(note);
    if (spares > 0) warm();
    return note;
  }

  /// The note closed: its page goes.
  void giveBack(WebNote note) {
    note.dispose();
    made.remove(note);
  }
}
