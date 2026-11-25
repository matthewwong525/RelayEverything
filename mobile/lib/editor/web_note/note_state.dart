import '../markdown.dart' show LineKind;

/// What the editor page says about its cursor after each change: the styles on the words picked, the line's kind,
/// whether it is in a table, Undo and Redo, and the find matches. The bars and menus light from it.
class NoteState {
  const NoteState({this.marks = const {}, this.highlight, this.link, this.kind, this.inTable = false,
    this.canUndo = false, this.canRedo = false, this.focus = false, this.editing = false, this.empty = true,
    this.found});

  /// `bold`, `italic`, `underline` and `strike` that are on every letter picked, or that the next letter takes.
  final Set<String> marks;
  /// The highlight colour of the words picked, or null.
  final String? highlight;
  /// The link on the words picked, or null.
  final String? link;
  /// The kind of the cursor's line; null on a file.
  final LineKind? kind;
  final bool inTable;
  final bool canUndo;
  final bool canRedo;
  /// The page's words have the keyboard's focus.
  final bool focus;
  /// The page edits: the person tapped in the words. While reading, a tap on a link opens it.
  final bool editing;
  /// No words are picked: the selection is a cursor.
  final bool empty;
  /// *Find in Note*: how many matches, and which one is selected; null while not finding.
  final ({int count, int index})? found;

  static NoteState fromJson(Map<Object?, Object?> json) {
    final found = json['found'];
    final kind = json['kind'];
    return NoteState(
      marks: {for (final mark in (json['marks'] as List?) ?? const []) '$mark'},
      highlight: json['highlight'] as String?,
      link: json['link'] as String?,
      kind: kind is String ? LineKind.values.where((one) => one.name == kind).firstOrNull : null,
      inTable: json['inTable'] == true,
      canUndo: json['canUndo'] == true,
      canRedo: json['canRedo'] == true,
      focus: json['focus'] == true,
      editing: json['editing'] == true,
      empty: json['empty'] != false,
      found: found is Map ? (count: _int(found['count']), index: _int(found['index'])) : null,
    );
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;
}
