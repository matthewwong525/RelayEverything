import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource, Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/editor/markdown.dart';
import 'package:relay_app/editor/paste.dart';

/// The Markdown a paste stores, which says each style in a line.
String fromHtml(String html, {String plain = ''}) => deltaToMarkdown(pastedDelta(html: html, plain: plain));
String fromPlain(String plain) => deltaToMarkdown(pastedDelta(plain: plain));

/// Every key in [delta]'s attributes.
Set<String> keysOf(Delta delta) => {for (final op in delta.toList()) ...?op.attributes?.keys};

/// [document] after [pasted] goes over [selection], and the caret after it.
(String, int) pasteInto(Delta document, TextSelection selection, Delta pasted) {
  final doc = Document.fromDelta(document);
  final paste = pasteChange(doc, selection, pasted)!;
  doc.compose(paste.change, ChangeSource.local);
  return (deltaToMarkdown(doc.toDelta()), paste.caret);
}

void main() {
  group('HTML keeps only the note\'s styles', () {
    test('a web page: a heading, bold words, a bullet list and a numbered list', () {
      expect(fromHtml('<h1>Trip to Lisbon</h1><p>Things to <b>book</b> first:</p>'
        '<ul><li>Flights</li><li>Hotel near <i>Alfama</i></li></ul><ol><li>Pack light</li></ol>'),
        '# Trip to Lisbon\nThings to **book** first:\n* Flights\n* Hotel near _Alfama_\n1. Pack light');
    });

    test('colors, fonts, sizes, backgrounds and alignment go', () {
      final delta = pastedDelta(plain: 'Red words\nMid', html: '<p><span style="color:red;font-size:30px;'
        'font-family:Georgia;background-color:yellow">Red</span> words</p><p style="text-align:center">Mid</p>');
      expect(deltaToMarkdown(delta), 'Red words\nMid');
      expect(keysOf(delta), isEmpty);
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
      final delta = pastedDelta(plain: '', html: '<p>Stops</p><table><thead><tr><th>Stop</th><th>Date</th></tr></thead>'
        '<tbody><tr><td><b>Toronto</b></td><td>Nov 20</td></tr><tr><td>Ottawa</td></tr></tbody></table><p>End</p>');
      expect(deltaToMarkdown(delta), 'Stops\n| Stop | Date |\n| --- | --- |\n| Toronto | Nov 20 |\n| Ottawa |  |\nEnd');
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
      expect(pastedDelta(plain: '## Plan\n- [ ] Call the bank\n- Buy **oat** milk').toJson(), [
        {'insert': 'Plan'}, {'insert': '\n', 'attributes': {'header': 2}},
        {'insert': 'Call the bank'}, {'insert': '\n', 'attributes': {'list': 'unchecked'}},
        {'insert': 'Buy '}, {'insert': 'oat', 'attributes': {'bold': true}}, {'insert': ' milk'},
        {'insert': '\n', 'attributes': {'list': 'dashed'}},
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
      expect(pastedDelta(plain: '').isEmpty, isTrue);
      expect(pastedDelta(plain: '\n\n', html: '<p> </p>').isEmpty, isTrue);
    });
  });

  test('each paste is what the note stores: it comes back the same from Markdown', () {
    final pastes = [
      pastedDelta(plain: '', html: '<h1>A</h1><p><b>b</b> <i>c</i> <u>d</u> <s>e</s></p><ul><li>f<ul><li>g</li></ul></li>'
        '</ul><blockquote>h</blockquote><pre>i\n\nj</pre>'),
      pastedDelta(plain: '# T\n- [x] a\n1. b\n2. c\n> q\n```\ncode\n```\n**x** _y_'),
      pastedDelta(plain: 'oat'),
    ];
    for (final delta in pastes) {
      expect(markdownToDelta(deltaToMarkdown(delta)), delta);
      expect((delta.toList().last.data as String).endsWith('\n'), isTrue);
    }
  });

  group('where a paste goes', () {
    final note = Delta()..insert('Buy milk')..insert('\n', {'list': 'unchecked'})..insert('Call Sam\n');

    test('one line with no style joins the line at the cursor, which keeps its style', () {
      expect(pasteInto(note, const TextSelection.collapsed(offset: 4), pastedDelta(plain: 'oat ')),
        ('- [ ] Buy oat milk\nCall Sam', 8));
    });

    test('a paste over selected words takes their place', () {
      expect(pasteInto(note, const TextSelection(baseOffset: 9, extentOffset: 17), pastedDelta(plain: '## Plan\n* a')),
        ('- [ ] Buy milk\n## Plan\n* a', 15));
    });

    test('lines pasted into the middle of a line: the words before keep their style, a styled last line stays its own',
        () {
      expect(pasteInto(note, const TextSelection.collapsed(offset: 4), pastedDelta(plain: 'oat\n* x')).$1,
        '- [ ] Buy oat\n* x\n- [ ] milk\nCall Sam');
    });

    test('lines pasted into a new note\'s empty Title line: the last one is not a Title', () {
      final empty = Delta()..insert('\n', {'header': 1});
      expect(pasteInto(empty, const TextSelection.collapsed(offset: 0), pastedDelta(plain: 'Para one\nPara two')),
        ('Para one\nPara two', 17));
      expect(pasteInto(empty, const TextSelection.collapsed(offset: 0), pastedDelta(plain: 'Only')), ('# Only', 4));
    });

    test('a Markdown table pasted as plain words is a table on its own line', () {
      final pasted = pastedDelta(plain: '| a | b |\n| --- | --- |\n| 1 | 2 |');
      expect(pasted.toList().where((op) => op.data is Map), hasLength(1));
      expect(pasteInto(note, const TextSelection.collapsed(offset: 4), pasted).$1,
        '- [ ] Buy \n| a | b |\n| --- | --- |\n| 1 | 2 |\n- [ ] milk\nCall Sam');
      expect(pasteInto(note, const TextSelection.collapsed(offset: 9), pasted).$1,
        '- [ ] Buy milk\n| a | b |\n| --- | --- |\n| 1 | 2 |\nCall Sam');
    });

    test('nothing to put and nothing selected is no change', () {
      expect(pasteChange(Document.fromDelta(note), const TextSelection.collapsed(offset: 4), Delta()), isNull);
    });
  });
}
