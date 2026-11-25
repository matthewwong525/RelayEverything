import 'markdown.dart';
import 'shortcuts.dart';
import 'web_note/web_note.dart';

/// The words picked, or the cursor's line, in a note: the styles they have, and each style the format tools set. The
/// Format sheet, the bars, the computer's menu and keys, and the Mac's *Format* menu all style through this. The note's
/// editor page does each change; this reads the page's last [NoteState].
class NoteCommands {
  const NoteCommands(this.page);

  final WebNote page;

  NoteState get _state => page.state;

  /// Whether the words picked, or the next letter typed, have [mark]: `bold`, `italic`, `underline` or `strike`.
  bool has(String mark) => _state.marks.contains(mark);

  /// The highlight colour of the words picked, or null.
  String? get highlight => _state.highlight;

  /// Whether the words picked hold a link.
  bool get linked => _state.link != null;

  /// The kind of the cursor's line.
  LineKind? get kind => _state.kind;

  /// The list kind of the cursor's line, such as [LineKind.bullet], or null.
  LineKind? get list => switch (kind) {
    LineKind.bullet || LineKind.dashed || LineKind.numbered || LineKind.unchecked || LineKind.checked => kind,
    _ => null,
  };

  /// The cursor's line style: Title, Heading, Subheading, Monostyled or Body.
  FormatAction get lineStyle => switch (kind) {
    LineKind.code => FormatAction.monostyled,
    LineKind.header1 => FormatAction.title,
    LineKind.header2 => FormatAction.heading,
    LineKind.header3 => FormatAction.subheading,
    _ => FormatAction.body,
  };

  /// [mark] on the words picked, or off when they all have it. At a cursor, the next letters typed.
  void toggle(String mark) => page.run(mark);

  /// The highlight pen: [colour] on the words picked, or off when they have a highlight.
  void highlightWith(String colour) => page.run('highlight', colour);

  /// Words with a highlight take [colour] in place of their own.
  void recolour(String colour) => page.run('recolour', colour);

  /// Does [action], with [colour] for the highlight pen. False for *Link* and *Table*, which the note page does itself.
  bool run(FormatAction action, {String colour = 'purple'}) {
    switch (action) {
      case FormatAction.bold: toggle('bold');
      case FormatAction.italic: toggle('italic');
      case FormatAction.underline: toggle('underline');
      case FormatAction.strikethrough: toggle('strike');
      case FormatAction.highlight: highlightWith(colour);
      case FormatAction.title: page.run('line', 'title');
      case FormatAction.heading: page.run('line', 'heading');
      case FormatAction.subheading: page.run('line', 'subheading');
      case FormatAction.body: page.run('line', 'body');
      case FormatAction.monostyled: page.run('line', 'monostyled');
      case FormatAction.bulleted: page.run('list', 'bullet');
      case FormatAction.dashed: page.run('list', 'dashed');
      case FormatAction.numbered: page.run('list', 'numbered');
      case FormatAction.checklist: page.run('checklist');
      case FormatAction.tick: page.run('tick');
      case FormatAction.quote: page.run('quote');
      case FormatAction.indentMore: page.run('indent', 1);
      case FormatAction.indentLess: page.run('indent', -1);
      case FormatAction.link || FormatAction.table: return false;
    }
    return true;
  }
}
