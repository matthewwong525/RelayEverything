import 'dart:math';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/editor/attachments.dart';
import 'package:relay_app/editor/markdown.dart';
import 'package:relay_app/editor/table.dart';
import 'package:super_editor/super_editor.dart';

/// Markdown read into the editor's nodes and written back.
String roundTrip(String markdown, {bool title = false}) => documentToMarkdown(markdownToNodes(markdown, title: title));

/// Each node in short: a line's kind, indent and runs of marked words; a table's rows; a file's id and name.
List<Object> shapeOf(List<DocumentNode> nodes) => [
  for (final node in nodes)
    switch (node) {
      NoteTableNode(:final table) => table.rows,
      AttachmentNode(:final file) => (file.id, file.name),
      TextNode() => [kindOf(node).name, indentOf(node), ...runsIn(node)],
      _ => node,
    },
];

/// Each run of a line's words with its marks, as `words[mark, mark]`.
List<String> runsIn(TextNode node) => [for (final (words, marks) in runsOf(node.text)) '$words${marks.toList()..sort()}'];

/// A body line of [runs], each words with their marks.
TextNode line(List<(String, Set<String>)> runs, [LineKind kind = LineKind.paragraph]) => lineNode(kind, attributedOf(runs));

/// Every mark key in [nodes]' words.
Set<String> marksIn(List<DocumentNode> nodes) => {
  for (final node in nodes) if (node is TextNode) for (final (_, marks) in runsOf(node.text)) ...marks,
};

/// The table in [markdown], which holds one.
NoteTable markdownTable(String markdown) => markdownToNodes(markdown).whereType<NoteTableNode>().first.table;

void main() {
  group('each style comes back byte for byte', () {
    const notes = {
      'Title': '# Shopping',
      'Heading': '## This week',
      'Subheading': '### Monday',
      'Monostyled': '```\nflutter test\n  --name editor\n```',
      'bulleted': '* Milk\n* Eggs',
      'dashed': '- Milk\n- Eggs',
      'numbered': '1. Wake\n2. Run\n3. Eat',
      'checklist': '- [ ] Eggs\n- [x] Milk',
      'quote': '> Less, but better.',
      'indent': '* Fruit\n  * Apples\n    * Green\n* Bread',
      'numbered in a bullet': '* Fruit\n  1. Apples\n  2. Pears\n* Bread',
      'bold': 'Buy **fresh** milk',
      'italic': 'Buy _fresh_ milk',
      'strike': 'Buy ~~fresh~~ milk',
      'underline': 'Buy <u>fresh</u> milk',
      'nested': '**bold _and italic_ words**',
      'italic inside a word': '*foo*bar and re*think*ing',
      'bold then italic inside a word': '**foo***bar*baz',
      'italic in bold inside a word': 'x*a**b***y',
      'two code blocks': '```\none\n```\n\n```\ntwo\n```',
      'all four': '**_~~<u>all</u>~~_**',
      'a whole note': '# Trip\nPack the bags.\n\n## List\n- [ ] Passport\n- [x] Tickets\n* Call **Mum**\n> Go slow',
    };
    for (final MapEntry(key: name, value: markdown) in notes.entries) {
      test(name, () => expect(roundTrip(markdown), markdown));
    }
  });

  test('reads each style as the editor draws it', () {
    expect(shapeOf(markdownToNodes('# Shop\n- [ ] Eggs\n**Milk**')), [
      ['header1', 0, 'Shop[]'], ['unchecked', 0, 'Eggs[]'], ['paragraph', 0, 'Milk[bold]'],
    ]);
  });

  test('a plain old note with stray marks comes back unchanged', () {
    const corpus = [
      'Price was 5 * 3 = 15',
      '#hashtag and # alone',
      '- ',
      '-dash with no space',
      'snake_case_name and _private',
      '2020. was a year',
      '3. is not the first number',
      'a ** lone pair ** of stars',
      '**not closed',
      '~~ spaced ~~',
      '<u>not closed',
      '```\nno closing fence',
      '```\n```',
      '   three spaces',
      'Line one\n\n\nLine four  ',
      '* [ ] not a checklist',
      '>quote with no space',
      'émoji 🎉 and ünïcode_',
      'I *really* mean it',
      '2 * 3 * 4',
      '***',
      '* a bullet with a star*',
    ];
    for (final note in corpus) {
      expect(roundTrip(note), note, reason: note);
    }
  });

  /// Each letter with its styles: spaces may lose theirs, as a style's edge spaces go outside its marks.
  List<String> styled(List<DocumentNode> nodes) => [
    for (final node in nodes.whereType<TextNode>())
      for (final (words, marks) in runsOf(node.text))
        for (final char in words.split(''))
          if (char.trim().isNotEmpty) '$char ${marks.toList()..sort()}',
  ];

  group('italic on part of a word', () {
    test('is written with stars and reads back as italic', () {
      expect(documentToMarkdown([line([('foo', {'italic'}), ('bar', {})])]), '*foo*bar');
      expect(shapeOf(markdownToNodes('*foo*bar')), [['paragraph', 0, 'foo[italic]', 'bar[]']]);
      expect(documentToMarkdown([line([('re', {}), ('think', {'italic'}), ('ing', {})])]), 're*think*ing');
      expect(shapeOf(markdownToNodes('re*think*ing')), [['paragraph', 0, 're[]', 'think[italic]', 'ing[]']]);
    });

    test('a whole word stays with underscores, and snake_case and a bullet stay as typed', () {
      expect(documentToMarkdown([line([('Buy ', {}), ('fresh', {'italic'}), (' milk', {})])]), 'Buy _fresh_ milk');
      expect(shapeOf(markdownToNodes('snake_case_name')), [['paragraph', 0, 'snake_case_name[]']]);
      expect(shapeOf(markdownToNodes('* foo*bar')), [['bullet', 0, 'foo*bar[]']]);
    });

    test('any mix of styles on any words comes back the same', () {
      final random = Random(7);
      const keys = ['bold', 'italic', 'strike', 'underline'];
      for (var round = 0; round < 3000; round++) {
        // A line that starts with spaces is indented, so each starts with a letter.
        final runs = <(String, Set<String>)>[('x', {})];
        for (var run = random.nextInt(5) + 1; run > 0; run--) {
          final words = String.fromCharCodes([for (var i = random.nextInt(4) + 1; i > 0; i--) 'ab '.codeUnitAt(random.nextInt(3))]);
          runs.add((words, {for (final key in keys) if (random.nextInt(3) == 0) key}));
        }
        final nodes = [line(runs)];
        final markdown = documentToMarkdown(nodes);
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(plainText(markdown), runs.map((run) => run.$1).join(), reason: markdown);
        expect(styled(markdownToNodes(markdown)), styled(nodes), reason: markdown);
      }
    });
  });

  test('two code blocks that touch stay two after an edit', () {
    final nodes = markdownToNodes('```\none\n```\n```\ntwo\n```');
    expect(shapeOf(nodes), [['code', 0, 'one[]'], ['code', 0, 'two[]']]);
    expect(documentToMarkdown(nodes), '```\none\n```\n```\ntwo\n```');
  });

  test('spaces at a style edge go outside its marks', () {
    expect(documentToMarkdown([line([('Buy ', {}), ('fresh ', {'bold'}), ('milk', {})])]), 'Buy **fresh** milk');
  });

  test('a link pasted in keeps its words and its link; a colour goes', () {
    final text = AttributedText('site')
      ..addAttribution(LinkAttribution('https://example.com'), const SpanRange(0, 3))
      ..addAttribution(const ColorAttribution(Color(0xffff0000)), const SpanRange(0, 3));
    expect(documentToMarkdown([lineNode(LineKind.paragraph, text)]), '[site](https://example.com)');
  });

  group('highlight', () {
    for (final colour in highlightColours) {
      test('$colour comes back byte for byte and reads as its colour', () {
        final markdown = 'Book the <mark class="$colour">hall</mark> today';
        expect(roundTrip(markdown), markdown);
        expect(runsOf((markdownToNodes(markdown).single as TextNode).text)[1].$2, {'mark:$colour'});
      });
    }

    test('a highlight beside and around bold words', () {
      for (final markdown in ['**Book** <mark class="pink">the hall</mark>', '<mark class="green">**now**</mark> then',
          '<mark class="blue">a **b** c</mark>']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
      }
      final nodes = [line([('hall', {'mark:pink', 'bold'})])];
      expect(documentToMarkdown(nodes), '<mark class="pink">**hall**</mark>');
      expect(shapeOf(markdownToNodes(documentToMarkdown(nodes))), shapeOf(nodes));
    });

    test('a mark with another class, or none, stays as words', () {
      for (final markdown in ['<mark class="red">x</mark>', '<mark>x</mark>', 'a <mark class="pink">b']) {
        expect(shapeOf(markdownToNodes(markdown)), [['paragraph', 0, '$markdown[]']], reason: markdown);
        expect(roundTrip(markdown), markdown);
      }
    });

    test('a colour the note has no name for is not written', () {
      final text = AttributedText('hall')..addAttribution(const HighlightAttribution('#ff0000'), const SpanRange(0, 3));
      expect(documentToMarkdown([lineNode(LineKind.paragraph, text)]), 'hall');
    });
  });

  group('links on words', () {
    test('read as a link and written back the same', () {
      for (final markdown in ['See [the menu](https://example.com/menu) now', 'Mail [Sam](mailto:sam@example.com)',
          '[**bold** words](https://example.com)', 'A [wiki page](https://en.wikipedia.org/wiki/Bread_(food)).']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
      }
      expect(shapeOf(markdownToNodes('[the menu](https://example.com/menu)')),
        [['paragraph', 0, 'the menu[link:https://example.com/menu]']]);
    });

    test('an address shown as a link to itself writes no brackets', () {
      final nodes = [line([('Open ', {}), ('https://example.com/a', {'link:https://example.com/a'})])];
      expect(documentToMarkdown(nodes), 'Open https://example.com/a');
    });

    test('brackets that are not a link stay as words', () {
      for (final markdown in ['[x] (y)', '[ x](y)', '[x](a b)', 'f[1](2', '- [ ] Eggs']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(marksIn(markdownToNodes(markdown)).where((mark) => mark.startsWith('link:')), isEmpty, reason: markdown);
      }
    });
  });

  group('tables', () {
    test('a table from Claude, with alignment marks and its own spacing, comes back byte for byte', () {
      const markdown = 'Trip\n\n| Stop    | Date   |\n|:--------|-------:|\n| Toronto | Nov 20 |\n| Ottawa  | Nov 22 |\n\nDone';
      final nodes = markdownToNodes(markdown);
      expect(nodes.whereType<NoteTableNode>().single.table.rows, [['Stop', 'Date'], ['Toronto', 'Nov 20'], ['Ottawa', 'Nov 22']]);
      expect(documentToMarkdown(nodes), markdown);
      expect(plainText(markdown), 'Trip\n\nStop\tDate\nToronto\tNov 20\nOttawa\tNov 22\n\nDone');
    });

    test('a changed cell writes the plain form', () {
      final table = NoteTable.fromJson(markdownTable('| Stop | Date |\n|:--|--:|\n| Toronto | Nov 20 |').toJson())!;
      final changed = table.withRows([['Stop', 'Date'], ['Toronto', 'Nov 21']]);
      expect(documentToMarkdown([NoteTableNode(id: 't1', table: changed)]), '| Stop | Date |\n| --- | --- |\n| Toronto | Nov 21 |');
    });

    test('a pipe in a cell is kept as \\|', () {
      final table = NoteTable([['a', 'b'], ['x | y', 'z']]);
      final markdown = documentToMarkdown([NoteTableNode(id: 't1', table: table)]);
      expect(markdown, '| a | b |\n| --- | --- |\n| x \\| y | z |');
      expect(markdownTable(markdown).rows, [['a', 'b'], ['x | y', 'z']]);
    });

    test('two tables one after the other open as two tables again, byte for byte', () {
      final first = NoteTable([['Day', 'Train'], ['Mon', '9:00']]);
      final second = NoteTable([['Name', 'Seat'], ['Sam', '4A']]);
      final markdown = documentToMarkdown([NoteTableNode(id: 't1', table: first), NoteTableNode(id: 't2', table: second)]);
      expect(markdown, '| Day | Train |\n| --- | --- |\n| Mon | 9:00 |\n| Name | Seat |\n| --- | --- |\n| Sam | 4A |');
      final tables = [for (final node in markdownToNodes(markdown).whereType<NoteTableNode>()) node.table.rows];
      expect(tables, [first.rows, second.rows]);
      expect(roundTrip(markdown), markdown);
      const fromClaude = '| Stop | Date |\n|:--|--:|\n| Toronto | Nov 20 |\n|  A  | B |\n| - | - |\n| c | d |';
      expect(roundTrip(fromClaude), fromClaude);
    });

    test('a body row of - cells stays a row of the same table', () {
      const markdown = '| Day | Train |\n| --- | --- |\n| Mon | 9:00 |\n| Tue | Bus |\n| - | - |';
      final tables = [for (final node in markdownToNodes(markdown).whereType<NoteTableNode>()) node.table.rows];
      expect(tables, [
        [['Day', 'Train'], ['Mon', '9:00'], ['Tue', 'Bus'], ['-', '-']],
      ]);
      expect(roundTrip(markdown), markdown);
    });

    test('a line of pipes that is not a table stays words', () {
      for (final markdown in ['| a | b |', '| a | b |\n| x | y |', '| a | b |\n| --- |', 'a | b\n--- | ---']) {
        expect(markdownToNodes(markdown).every((node) => node is TextNode), isTrue, reason: markdown);
        expect(roundTrip(markdown), markdown, reason: markdown);
      }
    });
  });

  test('with title, a first line with no style shows as a Title, and only that', () {
    expect([for (final node in markdownToNodes('Shop\nEggs', title: true)) kindOf(node)], [LineKind.header1, LineKind.paragraph]);
    expect([for (final node in markdownToNodes('* Shop', title: true)) kindOf(node)], [LineKind.bullet]);
    expect([for (final node in markdownToNodes('', title: true)) kindOf(node)], [LineKind.paragraph]);
  });

  test('plain text drops the marks', () {
    expect(plainText('# Shop\n- [ ] Eggs\n* **Milk**\n> <u>soon</u>'), 'Shop\nEggs\nMilk\nsoon');
    expect(plainText('snake_case 5 * 3'), 'snake_case 5 * 3');
    expect(plainText(''), '');
  });

  group('files in the words', () {
    const note = '# Receipt\n![receipt.jpg](attachment:p1)\nTotal 12\n![Recording.wav](attachment:r1)';

    test('a file line comes back byte for byte, with words between files', () {
      final nodes = markdownToNodes(note);
      expect([for (final file in attachmentsIn(nodes)) (file.id, file.name)], [('p1', 'receipt.jpg'), ('r1', 'Recording.wav')]);
      expect(documentToMarkdown(nodes), note);
    });

    test('a line for a file the note does not keep stays words', () {
      final nodes = markdownToNodes(note, files: {'p1'});
      expect(nodes.whereType<AttachmentNode>(), hasLength(1));
      expect(documentToMarkdown(nodes), note, reason: 'the unknown line goes back as it came');
    });

    test('a name with brackets or a line break still makes one line that reads back', () {
      const file = NoteAttachment('f1', 'plan [v2]\n.pdf');
      expect(file.markdown, '![plan _v2__.pdf](attachment:f1)');
      expect(NoteAttachment.read(file.markdown)?.id, 'f1');
      expect(NoteAttachment.read('see ![a](attachment:f1)'), isNull, reason: 'only a whole line places a file');
    });

    test('plain words leave the file lines out', () {
      expect(plainText(note), 'Receipt\nTotal 12');
      expect(plainText('![receipt.jpg](attachment:p1)'), '');
    });

    test('a text names a file by its id, and loses only the lines asked for', () {
      expect(NoteAttachment.idsIn(note), {'p1', 'r1'});
      expect(NoteAttachment.without(note, {'p1'}), '# Receipt\nTotal 12\n![Recording.wav](attachment:r1)');
      expect(NoteAttachment.without(note, const {}), note);
    });

    test('each file keeps a line of its own, between lines of words', () {
      final nodes = [
        line([('Paid ', {})]),
        AttachmentNode(id: 'a', file: const NoteAttachment('p1', 'receipt.jpg')),
        line([('in cash', {})]),
        AttachmentNode(id: 'b', file: const NoteAttachment('p1', 'receipt.jpg')),
        AttachmentNode(id: 'c', file: const NoteAttachment('p2', 'box.jpg')),
      ];
      final markdown = documentToMarkdown(nodes);
      expect(markdown, 'Paid \n![receipt.jpg](attachment:p1)\nin cash\n'
        '![receipt.jpg](attachment:p1)\n![box.jpg](attachment:p2)');
      expect(shapeOf(markdownToNodes(markdown)), [['paragraph', 0, 'Paid []'], ('p1', 'receipt.jpg'),
        ['paragraph', 0, 'in cash[]'], ('p1', 'receipt.jpg'), ('p2', 'box.jpg')]);
    });
  });

  group('lines under a list item', () {
    test('a line indented to an item\'s words stays in that item, and the numbers count on past it', () {
      const markdown = 'Steps\n1. Rinse the cups\n   Why: the tea is cleaner\n2. Boil the kettle\n   Why: the leaves open';
      final nodes = markdownToNodes(markdown);
      expect(shapeOf(nodes), [
        ['paragraph', 0, 'Steps[]'],
        ['numbered', 0, 'Rinse the cups\nWhy: the tea is cleaner[]'],
        ['numbered', 0, 'Boil the kettle\nWhy: the leaves open[]'],
      ]);
      expect(itemNumbers(nodes).values, [1, 2]);
      expect(documentToMarkdown(nodes), markdown);
    });

    test('a continuation line keeps its styles, and a checklist item has one too', () {
      for (final markdown in ['* Pack the **blue** bag\n  then the _red_ one', '- [ ] Water the fern\n      twice a week',
          '- Pebble\n  Gravel']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(markdownToNodes(markdown), hasLength(1), reason: markdown);
      }
    });

    test('a blank line inside an item stays in it while a later line still continues the item', () {
      final nodes = [lineNode(LineKind.numbered, AttributedText('Sort the jars\n\nWhy: the lids differ')),
        lineNode(LineKind.numbered, AttributedText('Label the shelf'))];
      final markdown = documentToMarkdown(nodes);
      expect(shapeOf(markdownToNodes(markdown)), [
        ['numbered', 0, 'Sort the jars\n\nWhy: the lids differ[]'], ['numbered', 0, 'Label the shelf[]'],
      ]);
      expect(itemNumbers(markdownToNodes(markdown)).values, [1, 2]);
      expect(roundTrip(markdown), markdown);
      // With no indented line after them, blank lines end the item, as before.
      expect(shapeOf(markdownToNodes('* Sort the jars\n\nLabel the shelf')), [
        ['bullet', 0, 'Sort the jars[]'], ['paragraph', 0], ['paragraph', 0, 'Label the shelf[]'],
      ]);
      expect(shapeOf(markdownToNodes('* Sort the jars\n\n\n  Why: the lids differ')), [
        ['bullet', 0, 'Sort the jars\n\n\nWhy: the lids differ[]'],
      ]);
    });

    test('a stored item with a truly blank line inside writes back byte for byte', () {
      for (final markdown in ['1. Sort the jars\n\n   Why: the lids differ\n2. Label the shelf',
          '- [ ] Water the fern\n\n\n      twice a week']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(documentToMarkdown(markdownToNodes(markdown)).contains(RegExp(r' +\n')), isFalse, reason: markdown);
      }
    });

    test('a line not indented to the words ends the item', () {
      const markdown = '1. Rinse the cups\nWhy: the tea is cleaner\n1. Boil the kettle';
      expect(shapeOf(markdownToNodes(markdown)), [
        ['numbered', 0, 'Rinse the cups[]'], ['paragraph', 0, 'Why: the tea is cleaner[]'], ['numbered', 0, 'Boil the kettle[]'],
      ]);
      expect(roundTrip(markdown), markdown);
    });
  });

  test('a dashed sub-list under a dashed item stays dashed, a level in', () {
    const markdown = '- Garden\n  - Rake\n  - Hoe\n- Shed';
    final nodes = markdownToNodes(markdown);
    expect([for (final node in nodes) (kindOf(node), indentOf(node))], [
      (LineKind.dashed, 0), (LineKind.dashed, 1), (LineKind.dashed, 1), (LineKind.dashed, 0),
    ]);
    expect(documentToMarkdown(nodes), markdown);
  });
}
