import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/editor/markdown.dart';
import 'package:relay_app/editor/note_editing.dart' show documentSelectionOf, offsetAt;
import 'package:relay_app/editor/paste.dart' as paste_ show pasteInto;
import 'package:relay_app/editor/paste.dart' hide pasteInto;
import 'package:relay_app/editor/table.dart';
import 'package:super_editor/super_editor.dart';

/// The Markdown a paste stores, which says each style in a line.
String fromHtml(String html, {String plain = ''}) => documentToMarkdown(pastedNodes(html: html, plain: plain));
String fromPlain(String plain) => documentToMarkdown(pastedNodes(plain: plain));

/// Every mark key in [nodes]' words.
Set<String> marksIn(List<DocumentNode> nodes) => {
  for (final node in nodes) if (node is TextNode) for (final (_, marks) in runsOf(node.text)) ...marks,
};

/// Each node in short: a line's kind, indent and runs of marked words.
List<Object> shapeOf(List<DocumentNode> nodes) => [
  for (final node in nodes)
    if (node is TextNode)
      [kindOf(node).name, indentOf(node), for (final (words, marks) in runsOf(node.text)) '$words${marks.toList()..sort()}']
    else node.runtimeType,
];

/// The note of [markdown] after [pasted] goes over [selection], and the caret after it.
(String, int) pasteInto(String markdown, TextSelection selection, List<DocumentNode> pasted) {
  final nodes = markdownToNodes(markdown);
  final paste = paste_.pasteInto(nodes, documentSelectionOf(nodes, selection), pasted)!;
  return (documentToMarkdown(paste.nodes), offsetAt(paste.nodes, paste.caret.extent)!);
}

void main() {
  group('HTML keeps only the note\'s styles', () {
    test('a web page: a heading, bold words, a bullet list and a numbered list', () {
      expect(fromHtml('<h1>Trip to Lisbon</h1><p>Things to <b>book</b> first:</p>'
        '<ul><li>Flights</li><li>Hotel near <i>Alfama</i></li></ul><ol><li>Pack light</li></ol>'),
        '# Trip to Lisbon\nThings to **book** first:\n* Flights\n* Hotel near _Alfama_\n1. Pack light');
    });

    test('colors, fonts, sizes, backgrounds and alignment go', () {
      final nodes = pastedNodes(plain: 'Red words\nMid', html: '<p><span style="color:red;font-size:30px;'
        'font-family:Georgia;background-color:yellow">Red</span> words</p><p style="text-align:center">Mid</p>');
      expect(documentToMarkdown(nodes), 'Red words\nMid');
      expect(marksIn(nodes), isEmpty);
    });

    test('a heading past the third level is a subheading', () {
      expect(fromHtml('<h2>Two</h2><h4>Four</h4><h6>Six</h6>'), '## Two\n### Four\n### Six');
    });

    test('a link with its own words keeps its words linked; a bare address stays as it is', () {
      expect(fromHtml('<p>See <a href="https://example.com/menu">the menu</a> or '
        '<a href="https://example.com/">example.com</a>, mail <a href="mailto:sam@example.com">Sam</a>, '
        'go <a href="/inside">here</a>.</p>'),
        'See [the menu](https://example.com/menu) or example.com, mail [Sam](mailto:sam@example.com), go here.');
    });

    test('a table pastes as a table, with each cell\'s words', () {
      final nodes = pastedNodes(plain: '', html: '<p>Stops</p><table><thead><tr><th>Stop</th><th>Date</th></tr></thead>'
        '<tbody><tr><td><b>Toronto</b></td><td>Nov 20</td></tr><tr><td>Ottawa</td></tr></tbody></table><p>End</p>');
      expect(documentToMarkdown(nodes), 'Stops\n| Stop | Date |\n| --- | --- |\n| Toronto | Nov 20 |\n| Ottawa |  |\nEnd');
    });

    test('a page laid out in a table, or a table of one cell, pastes as words', () {
      expect(fromHtml('<table><tr><td><table><tr><td>a</td><td>b</td></tr></table></td></tr></table>'), isNot(contains('|')));
      expect(fromHtml('<table><tr><td>Only</td></tr></table>'), 'Only');
    });

    test('Google Docs\' bold wrapper is not bold, and its spans keep their own weight', () {
      expect(fromHtml('<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1a2b">'
        '<p dir="ltr" style="line-height:1.38;margin-top:0pt;"><span style="font-size:11pt;font-family:Arial;'
        'color:#000000;font-weight:700;">Bold</span><span style="font-size:11pt;font-weight:400;"> and plain</span></p>'
        '<br><ul style="margin-top:0;"><li dir="ltr" style="list-style-type:disc;font-weight:400;" aria-level="1">'
        '<p dir="ltr" role="presentation"><span style="font-weight:400;font-style:italic;">One</span></p></li>'
        '<li dir="ltr" aria-level="2"><p dir="ltr"><span style="text-decoration:underline;">Two</span></p></li>'
        '</ul></b>'),
        '**Bold** and plain\n\n* _One_\n  * <u>Two</u>');
    });

    test('Notion\'s and GitHub\'s checklists, and Quill\'s, keep their ticks', () {
      expect(fromHtml('<ul class="to-do-list"><li><div class="checkbox checkbox-off"></div> '
        '<span class="to-do-children-unchecked">Call the bank</span></li></ul><ul class="to-do-list"><li>'
        '<div class="checkbox checkbox-on"></div> <span class="to-do-children-checked">Book flights</span></li></ul>'),
        '- [ ] Call the bank\n- [x] Book flights');
      expect(fromHtml('<ul><li><input type="checkbox" checked disabled> Done</li><li><input type="checkbox"> Open'
        '</li></ul>'), '- [x] Done\n- [ ] Open');
      expect(fromHtml('<ul data-checked="true"><li>Milk</li></ul><ol><li data-list="unchecked">Eggs</li></ol>'),
        '- [x] Milk\n- [ ] Eggs');
    });

    test('a chat\'s HTML: numbered steps, a code block with no button words, and inline code as words', () {
      expect(fromHtml('<h3>Plan</h3><p>Steps:</p><ol><li><p><strong>Wake</strong> early</p></li><li><p>Run</p></li>'
        '</ol><pre><div><div><button>Copy code</button></div><div><code>flutter test\n  --name editor\n</code></div>'
        '</div></pre><p>Use <code>flutter</code> now.</p><blockquote><p>Less, but better.</p></blockquote>'),
        '### Plan\nSteps:\n1. **Wake** early\n2. Run\n```\nflutter test\n  --name editor\n```\nUse flutter now.\n'
        '> Less, but better.');
    });

    test('Apple Notes\' words, as the phone makes them from RTF: lists with levels, underline and strike', () {
      expect(fromHtml('<p><b>Groceries</b></p><ul><li aria-level="1">Milk</li><li aria-level="2"><i>Oat</i></li></ul>'
        '<ol><li aria-level="1">First</li></ol><p><br></p><p><u>Under</u> and <s>struck</s></p>'),
        '**Groceries**\n* Milk\n  * _Oat_\n1. First\n\n<u>Under</u> and ~~struck~~');
    });

    test('Word\'s list paragraphs lose the bullet and number it writes as words', () {
      expect(fromHtml("<p class=MsoListParagraphCxSpFirst style='mso-list:l0 level1 lfo1'><![if !supportLists]>"
        "<span style='font-family:Symbol'>·<span style='font:7.0pt \"Times New Roman\"'>&nbsp;&nbsp;&nbsp; </span>"
        "</span><![endif]>Apples</p><p style='mso-list:l1 level1 lfo2'><![if !supportLists]><span>1.<span>&nbsp;&nbsp; "
        "</span></span><![endif]>Count</p><p class=MsoNormal>After<o:p></o:p></p>"), '* Apples\n1. Count\nAfter');
    });

    test('spaces and line breaks in the page\'s code are not words; pictures and scripts go', () {
      expect(fromHtml('<div>\n  <p>One\n   two</p>\n  <img src="a.png"><script>alert(1)</script><p>Three</p></div>'),
        'One two\nThree');
    });

    test('HTML with no words, such as a picture, pastes the plain words', () {
      expect(fromHtml('<img src="photo.png">', plain: 'Photo'), 'Photo');
    });
  });

  group('plain words are read as Markdown', () {
    test('Markdown from a chat becomes a heading, a checklist item and a dashed item with bold words', () {
      expect(shapeOf(pastedNodes(plain: '## Plan\n- [ ] Call the bank\n- Buy **oat** milk')), [
        ['header2', 0, 'Plan[]'], ['unchecked', 0, 'Call the bank[]'], ['dashed', 0, 'Buy []', 'oat[bold]', ' milk[]'],
      ]);
    });

    test('words that only look like marks stay words', () {
      expect(fromPlain('2020. was a year\nsnake_case and 5 * 3'), '2020. was a year\nsnake_case and 5 * 3');
    });

    test('a bullet sign starts a bullet item', () {
      expect(fromPlain('• Milk\n◦ Oat\n▪ Eggs\nBread'), '* Milk\n* Oat\n* Eggs\nBread');
    });

    test('runs of empty lines become one, and empty lines at the start and end go', () {
      expect(fromPlain('\r\n\nOne\r\n\r\n\r\nTwo\n  \n\nThree\n\n'), 'One\n\nTwo\n\nThree');
    });

    test('nothing to paste is empty', () {
      expect(pastedNodes(plain: ''), isEmpty);
      expect(pastedNodes(plain: '\n\n', html: '<p> </p>'), isEmpty);
    });
  });

  test('each paste is what the note stores: it comes back the same from Markdown', () {
    final pastes = [
      pastedNodes(plain: '', html: '<h1>A</h1><p><b>b</b> <i>c</i> <u>d</u> <s>e</s></p><ul><li>f<ul><li>g</li></ul></li>'
        '</ul><blockquote>h</blockquote><pre>i\n\nj</pre>'),
      pastedNodes(plain: '# T\n- [x] a\n1. b\n2. c\n> q\n```\ncode\n```\n**x** _y_'),
      pastedNodes(plain: 'oat'),
    ];
    for (final nodes in pastes) {
      expect(shapeOf(markdownToNodes(documentToMarkdown(nodes))), shapeOf(nodes));
    }
  });

  group('where a paste goes', () {
    const note = '- [ ] Buy milk\nCall Sam';

    test('one line with no style joins the line at the cursor, which keeps its style', () {
      expect(pasteInto(note, const TextSelection.collapsed(offset: 4), pastedNodes(plain: 'oat ')),
        ('- [ ] Buy oat milk\nCall Sam', 8));
    });

    test('a paste over selected words takes their place', () {
      expect(pasteInto(note, const TextSelection(baseOffset: 9, extentOffset: 17), pastedNodes(plain: '## Plan\n* a')),
        ('- [ ] Buy milk\n## Plan\n* a', 15));
    });

    test('lines pasted into the middle of a line: the words before keep their style, a styled last line stays its own',
        () {
      expect(pasteInto(note, const TextSelection.collapsed(offset: 4), pastedNodes(plain: 'oat\n* x')).$1,
        '- [ ] Buy oat\n* x\n- [ ] milk\nCall Sam');
    });

    test('lines pasted into a new note\'s empty Title line: the last one is not a Title', () {
      const empty = '# ';
      expect(pasteInto(empty, const TextSelection.collapsed(offset: 0), pastedNodes(plain: 'Para one\nPara two')),
        ('Para one\nPara two', 17));
      expect(pasteInto(empty, const TextSelection.collapsed(offset: 0), pastedNodes(plain: 'Only')), ('# Only', 4));
    });

    test('a Markdown table pasted as plain words is a table on its own line', () {
      final pasted = pastedNodes(plain: '| a | b |\n| --- | --- |\n| 1 | 2 |');
      expect(pasted.whereType<NoteTableNode>(), hasLength(1));
      expect(pasteInto(note, const TextSelection.collapsed(offset: 4), pasted).$1,
        '- [ ] Buy \n| a | b |\n| --- | --- |\n| 1 | 2 |\n- [ ] milk\nCall Sam');
      expect(pasteInto(note, const TextSelection.collapsed(offset: 9), pasted).$1,
        '- [ ] Buy milk\n| a | b |\n| --- | --- |\n| 1 | 2 |\nCall Sam');
    });

    test('nothing to put and nothing selected is no change', () {
      final nodes = markdownToNodes(note);
      expect(paste_.pasteInto(nodes, documentSelectionOf(nodes, const TextSelection.collapsed(offset: 4)), const []), isNull);
    });
  });

  group('a plan pasted as plain words', () {
    test('an indented numbered list under a label pastes as 1, 2, 3 with each Why: line under its item', () {
      const plain = 'Garden plan\n   1. Plant the beans\n      Why: the soil is warm\n   2. Water the roses\n'
        '      Why: the leaves are dry\n   3. Rake the path\n      Why: the gate sticks';
      final nodes = pastedNodes(plain: plain);
      expect(shapeOf(nodes), [
        ['paragraph', 0, 'Garden plan[]'],
        ['numbered', 0, 'Plant the beans\nWhy: the soil is warm[]'],
        ['numbered', 0, 'Water the roses\nWhy: the leaves are dry[]'],
        ['numbered', 0, 'Rake the path\nWhy: the gate sticks[]'],
      ]);
      expect(itemNumbers(nodes).values, [1, 2, 3]);
      expect(documentToMarkdown(nodes), 'Garden plan\n1. Plant the beans\n   Why: the soil is warm\n2. Water the roses\n'
        '   Why: the leaves are dry\n3. Rake the path\n   Why: the gate sticks');
    });

    test('a real sub-list stays a sub-list', () {
      final nodes = pastedNodes(plain: '1. Plant the beans\n   - Green\n   - Runner\n2. Water the roses');
      expect([for (final node in nodes) (kindOf(node), indentOf(node))], [
        (LineKind.numbered, 0), (LineKind.dashed, 1), (LineKind.dashed, 1), (LineKind.numbered, 0),
      ]);
      expect(itemNumbers(nodes).values, [1, 2]);
    });

    test('a line break inside a page\'s list item starts a line in that item, and the numbers count on past it', () {
      final nodes = pastedNodes(html: '<ol><li>Pack the crate <br> Why: tape the lid</li><li>Ship it<br></li></ol>',
        plain: '');
      expect(shapeOf(nodes), [
        ['numbered', 0, 'Pack the crate\nWhy: tape the lid[]'],
        ['numbered', 0, 'Ship it[]'],
      ]);
      expect(itemNumbers(nodes).values, [1, 2]);
      expect(documentToMarkdown(nodes), '1. Pack the crate\n   Why: tape the lid\n2. Ship it');
    });

    test('the space a page puts after a line break in a list item does not start the line under it', () {
      final nodes = pastedNodes(html: '<ol><li>Pack<br>\n Why: tape</li></ol>', plain: '');
      expect(shapeOf(nodes), [['numbered', 0, 'Pack\nWhy: tape[]']]);
      expect(documentToMarkdown(nodes), '1. Pack\n   Why: tape');
    });

    test('a tab-indented list starts at the left, and a tab a level in is a sub-list', () {
      final nodes = pastedNodes(plain: '\t* Pebble\n\t\t* Gravel');
      expect([for (final node in nodes) (kindOf(node), indentOf(node))], [(LineKind.bullet, 0), (LineKind.bullet, 1)]);
    });
  });
}
