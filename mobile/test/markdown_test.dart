import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/editor/markdown.dart';

import 'golden_notes.dart';

/// [markdown] as the editor page gets it: its document, sent as JSON text, read back into blocks.
List<NoteBlock> read(String markdown, {bool title = false, Set<String>? files}) =>
  docToBlocks((jsonDecode(jsonEncode(markdownToDoc(markdown, title: title, files: files))) as Map).cast());

/// [blocks] as the page sends them back, as Markdown.
String written(List<NoteBlock> blocks) => docToMarkdown((jsonDecode(jsonEncode(blocksToDoc(blocks))) as Map).cast());

/// Markdown read into the page's document and written back.
String roundTrip(String markdown, {bool title = false}) => written(read(markdown, title: title));

/// Each block in short: a line's kind, indent and runs of marked words; a table's rows; a file's id and name.
List<Object> shapeOf(List<NoteBlock> blocks) => [
  for (final block in blocks)
    switch (block) {
      NoteTableBlock(:final table) => table.rows,
      NoteFileBlock(:final file) => (file.id, file.name),
      NoteLine() => [block.kind.name, block.indent, ...runsIn(block)],
    },
];

/// Each run of a line's words with its marks, as `words[mark, mark]`.
List<String> runsIn(NoteLine line) => [for (final (words, marks) in line.runs) '$words${marks.toList()..sort()}'];

/// A body line of [runs], each words with their marks.
NoteLine line(List<(String, Set<String>)> runs, [LineKind kind = LineKind.paragraph]) => NoteLine(kind, runs);

/// Every mark key in [blocks]' words.
Set<String> marksIn(List<NoteBlock> blocks) => {
  for (final block in blocks) if (block is NoteLine) for (final (_, marks) in block.runs) ...marks,
};

/// The table in [markdown], which holds one.
NoteTable markdownTable(String markdown) => read(markdown).whereType<NoteTableBlock>().first.table;

/// A page document of one paragraph of [nodes].
Json docOf(List<Json> nodes) => {'type': 'doc', 'content': [{'type': 'paragraph', 'attrs': {'indent': 0}, 'content': nodes}]};

void main() {
  test('every golden note comes back byte for byte through the page\'s document', () {
    for (final note in goldenNotes) {
      expect(roundTrip(note), note, reason: note);
    }
  });

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
    expect(shapeOf(read('# Shop\n- [ ] Eggs\n**Milk**')), [
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
  List<String> styled(List<NoteBlock> blocks) => [
    for (final block in blocks.whereType<NoteLine>())
      for (final (words, marks) in block.runs)
        for (final char in words.split(''))
          if (char.trim().isNotEmpty) '$char ${marks.toList()..sort()}',
  ];

  group('italic on part of a word', () {
    test('is written with stars and reads back as italic', () {
      expect(written([line([('foo', {'italic'}), ('bar', {})])]), '*foo*bar');
      expect(shapeOf(read('*foo*bar')), [['paragraph', 0, 'foo[italic]', 'bar[]']]);
      expect(written([line([('re', {}), ('think', {'italic'}), ('ing', {})])]), 're*think*ing');
      expect(shapeOf(read('re*think*ing')), [['paragraph', 0, 're[]', 'think[italic]', 'ing[]']]);
    });

    test('a whole word stays with underscores, and snake_case and a bullet stay as typed', () {
      expect(written([line([('Buy ', {}), ('fresh', {'italic'}), (' milk', {})])]), 'Buy _fresh_ milk');
      expect(shapeOf(read('snake_case_name')), [['paragraph', 0, 'snake_case_name[]']]);
      expect(shapeOf(read('* foo*bar')), [['bullet', 0, 'foo*bar[]']]);
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
        final markdown = written(nodes);
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(plainText(markdown), runs.map((run) => run.$1).join(), reason: markdown);
        expect(styled(read(markdown)), styled(nodes), reason: markdown);
      }
    });
  });

  test('two code blocks that touch stay two after an edit', () {
    final nodes = read('```\none\n```\n```\ntwo\n```');
    expect(shapeOf(nodes), [['code', 0, 'one[]'], ['code', 0, 'two[]']]);
    expect(written(nodes), '```\none\n```\n```\ntwo\n```');
  });

  test('spaces at a style edge go outside its marks', () {
    expect(written([line([('Buy ', {}), ('fresh ', {'bold'}), ('milk', {})])]), 'Buy **fresh** milk');
  });

  test('a link from the page keeps its words and its link; a colour goes', () {
    expect(docToMarkdown(docOf([{'type': 'text', 'text': 'site', 'marks': [
      {'type': 'link', 'attrs': {'href': 'https://example.com', 'auto': false}},
      {'type': 'textStyle', 'attrs': {'color': '#ff0000'}},
    ]}])), '[site](https://example.com)');
  });

  group('highlight', () {
    for (final colour in highlightColours) {
      test('$colour comes back byte for byte and reads as its colour', () {
        final markdown = 'Book the <mark class="$colour">hall</mark> today';
        expect(roundTrip(markdown), markdown);
        expect((read(markdown).single as NoteLine).runs[1].$2, {'mark:$colour'});
      });
    }

    test('a highlight beside and around bold words', () {
      for (final markdown in ['**Book** <mark class="pink">the hall</mark>', '<mark class="green">**now**</mark> then',
          '<mark class="blue">a **b** c</mark>']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
      }
      final nodes = [line([('hall', {'mark:pink', 'bold'})])];
      expect(written(nodes), '<mark class="pink">**hall**</mark>');
      expect(shapeOf(read(written(nodes))), shapeOf(nodes));
    });

    test('a mark with another class, or none, stays as words', () {
      for (final markdown in ['<mark class="red">x</mark>', '<mark>x</mark>', 'a <mark class="pink">b']) {
        expect(shapeOf(read(markdown)), [['paragraph', 0, '$markdown[]']], reason: markdown);
        expect(roundTrip(markdown), markdown);
      }
    });

    test('a colour the note has no name for is not written', () {
      expect(docToMarkdown(docOf([{'type': 'text', 'text': 'hall', 'marks': [
        {'type': 'highlight', 'attrs': {'colour': '#ff0000'}},
      ]}])), 'hall');
    });
  });

  group('links on words', () {
    test('read as a link and written back the same', () {
      for (final markdown in ['See [the menu](https://example.com/menu) now', 'Mail [Sam](mailto:sam@example.com)',
          '[**bold** words](https://example.com)', 'A [wiki page](https://en.wikipedia.org/wiki/Bread_(food)).']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
      }
      expect(shapeOf(read('[the menu](https://example.com/menu)')),
        [['paragraph', 0, 'the menu[link:https://example.com/menu]']]);
    });

    test('an address shown as a link to itself writes no brackets, and a link the page made on an address is none', () {
      final nodes = [line([('Open ', {}), ('https://example.com/a', {'link:https://example.com/a'})])];
      expect(written(nodes), 'Open https://example.com/a');
      expect(docToMarkdown(docOf([{'type': 'text', 'text': 'Open '}, {'type': 'text', 'text': 'example.com/a_b', 'marks': [
        {'type': 'link', 'attrs': {'href': 'https://example.com/a_b', 'auto': true}},
      ]}])), 'Open example.com/a_b');
    });

    test('brackets that are not a link stay as words', () {
      for (final markdown in ['[x] (y)', '[ x](y)', '[x](a b)', 'f[1](2', '- [ ] Eggs']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(marksIn(read(markdown)).where((mark) => mark.startsWith('link:')), isEmpty, reason: markdown);
      }
    });
  });

  group('tables', () {
    test('a table from Claude, with alignment marks and its own spacing, comes back byte for byte', () {
      const markdown = 'Trip\n\n| Stop    | Date   |\n|:--------|-------:|\n| Toronto | Nov 20 |\n| Ottawa  | Nov 22 |\n\nDone';
      final nodes = read(markdown);
      expect(nodes.whereType<NoteTableBlock>().single.table.rows, [['Stop', 'Date'], ['Toronto', 'Nov 20'], ['Ottawa', 'Nov 22']]);
      expect(written(nodes), markdown);
      expect(plainText(markdown), 'Trip\n\nStop\tDate\nToronto\tNov 20\nOttawa\tNov 22\n\nDone');
    });

    test('a changed cell writes the plain form', () {
      final table = NoteTable.fromJson(markdownTable('| Stop | Date |\n|:--|--:|\n| Toronto | Nov 20 |').toJson())!;
      final changed = table.withRows([['Stop', 'Date'], ['Toronto', 'Nov 21']]);
      expect(written([NoteTableBlock(changed)]), '| Stop | Date |\n| --- | --- |\n| Toronto | Nov 21 |');
      // A cell the page changed, with the table's own Markdown still beside it, writes the plain form too.
      final doc = markdownToDoc('| Stop | Date |\n|:--|--:|\n| Toronto | Nov 20 |');
      final cell = ((((((doc['content']! as List).single as Map)['content']! as List)[1] as Map)['content']! as List)[1] as Map);
      cell['content'] = [{'type': 'paragraph', 'content': [{'type': 'text', 'text': 'Nov 21'}]}];
      expect(docToMarkdown(doc), '| Stop | Date |\n| --- | --- |\n| Toronto | Nov 21 |');
    });

    test('a pipe in a cell is kept as \\|', () {
      final table = NoteTable([['a', 'b'], ['x | y', 'z']]);
      final markdown = written([NoteTableBlock(table)]);
      expect(markdown, '| a | b |\n| --- | --- |\n| x \\| y | z |');
      expect(markdownTable(markdown).rows, [['a', 'b'], ['x | y', 'z']]);
    });

    test('two tables one after the other open as two tables again, byte for byte', () {
      final first = NoteTable([['Day', 'Train'], ['Mon', '9:00']]);
      final second = NoteTable([['Name', 'Seat'], ['Sam', '4A']]);
      final markdown = written([NoteTableBlock(first), NoteTableBlock(second)]);
      expect(markdown, '| Day | Train |\n| --- | --- |\n| Mon | 9:00 |\n| Name | Seat |\n| --- | --- |\n| Sam | 4A |');
      final tables = [for (final block in read(markdown).whereType<NoteTableBlock>()) block.table.rows];
      expect(tables, [first.rows, second.rows]);
      expect(roundTrip(markdown), markdown);
      const fromClaude = '| Stop | Date |\n|:--|--:|\n| Toronto | Nov 20 |\n|  A  | B |\n| - | - |\n| c | d |';
      expect(roundTrip(fromClaude), fromClaude);
    });

    test('a body row of - cells stays a row of the same table', () {
      const markdown = '| Day | Train |\n| --- | --- |\n| Mon | 9:00 |\n| Tue | Bus |\n| - | - |';
      final tables = [for (final block in read(markdown).whereType<NoteTableBlock>()) block.table.rows];
      expect(tables, [
        [['Day', 'Train'], ['Mon', '9:00'], ['Tue', 'Bus'], ['-', '-']],
      ]);
      expect(roundTrip(markdown), markdown);
    });

    test('a line of pipes that is not a table stays words', () {
      for (final markdown in ['| a | b |', '| a | b |\n| x | y |', '| a | b |\n| --- |', 'a | b\n--- | ---']) {
        expect(read(markdown).every((block) => block is NoteLine), isTrue, reason: markdown);
        expect(roundTrip(markdown), markdown, reason: markdown);
      }
    });
  });

  test('with title, a first line with no style shows as a Title, and only that', () {
    List<LineKind> kinds(String markdown) => [for (final block in read(markdown, title: true)) (block as NoteLine).kind];
    expect(kinds('Shop\nEggs'), [LineKind.header1, LineKind.paragraph]);
    expect(kinds('* Shop'), [LineKind.bullet]);
    expect(kinds(''), [LineKind.paragraph]);
    // The page draws the Title line as a Title; once changed, its text gains `# `.
    final doc = markdownToDoc('Shop\nEggs', title: true);
    expect(((doc['content']! as List).first as Map)['attrs'], {'level': 1, 'indent': 0, 'title': true});
    expect(docToMarkdown(doc), '# Shop\nEggs');
  });

  test('plain text drops the marks', () {
    expect(plainText('# Shop\n- [ ] Eggs\n* **Milk**\n> <u>soon</u>'), 'Shop\nEggs\nMilk\nsoon');
    expect(plainText('snake_case 5 * 3'), 'snake_case 5 * 3');
    expect(plainText(''), '');
  });

  group('files in the words', () {
    const note = '# Receipt\n![receipt.jpg](attachment:p1)\nTotal 12\n![Recording.wav](attachment:r1)';

    test('a file line comes back byte for byte, with words between files', () {
      final nodes = read(note);
      expect([for (final file in attachmentsIn(nodes)) (file.id, file.name)], [('p1', 'receipt.jpg'), ('r1', 'Recording.wav')]);
      expect(written(nodes), note);
    });

    test('a line for a file the note does not keep stays words', () {
      final nodes = read(note, files: {'p1'});
      expect(nodes.whereType<NoteFileBlock>(), hasLength(1));
      expect(written(nodes), note, reason: 'the unknown line goes back as it came');
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
        const NoteFileBlock(NoteAttachment('p1', 'receipt.jpg')),
        line([('in cash', {})]),
        const NoteFileBlock(NoteAttachment('p1', 'receipt.jpg')),
        const NoteFileBlock(NoteAttachment('p2', 'box.jpg')),
      ];
      final markdown = written(nodes);
      expect(markdown, 'Paid \n![receipt.jpg](attachment:p1)\nin cash\n'
        '![receipt.jpg](attachment:p1)\n![box.jpg](attachment:p2)');
      expect(shapeOf(read(markdown)), [['paragraph', 0, 'Paid []'], ('p1', 'receipt.jpg'),
        ['paragraph', 0, 'in cash[]'], ('p1', 'receipt.jpg'), ('p2', 'box.jpg')]);
    });
  });

  group('lines under a list item', () {
    test('a line indented to an item\'s words stays in that item, and the numbers count on past it', () {
      const markdown = 'Steps\n1. Rinse the cups\n   Why: the tea is cleaner\n2. Boil the kettle\n   Why: the leaves open';
      final nodes = read(markdown);
      expect(shapeOf(nodes), [
        ['paragraph', 0, 'Steps[]'],
        ['numbered', 0, 'Rinse the cups\nWhy: the tea is cleaner[]'],
        ['numbered', 0, 'Boil the kettle\nWhy: the leaves open[]'],
      ]);
      expect(itemNumbers(nodes).values, [1, 2]);
      expect(written(nodes), markdown);
    });

    test('a continuation line keeps its styles, and a checklist item has one too', () {
      for (final markdown in ['* Pack the **blue** bag\n  then the _red_ one', '- [ ] Water the fern\n      twice a week',
          '- Pebble\n  Gravel']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(read(markdown), hasLength(1), reason: markdown);
      }
    });

    test('a blank line inside an item stays in it while a later line still continues the item', () {
      final nodes = [NoteLine.plain(LineKind.numbered, 'Sort the jars\n\nWhy: the lids differ'),
        NoteLine.plain(LineKind.numbered, 'Label the shelf')];
      final markdown = written(nodes);
      expect(shapeOf(read(markdown)), [
        ['numbered', 0, 'Sort the jars\n\nWhy: the lids differ[]'], ['numbered', 0, 'Label the shelf[]'],
      ]);
      expect(itemNumbers(read(markdown)).values, [1, 2]);
      expect(roundTrip(markdown), markdown);
      // With no indented line after them, blank lines end the item, as before.
      expect(shapeOf(read('* Sort the jars\n\nLabel the shelf')), [
        ['bullet', 0, 'Sort the jars[]'], ['paragraph', 0], ['paragraph', 0, 'Label the shelf[]'],
      ]);
      expect(shapeOf(read('* Sort the jars\n\n\n  Why: the lids differ')), [
        ['bullet', 0, 'Sort the jars\n\n\nWhy: the lids differ[]'],
      ]);
    });

    test('a stored item with a truly blank line inside writes back byte for byte', () {
      for (final markdown in ['1. Sort the jars\n\n   Why: the lids differ\n2. Label the shelf',
          '- [ ] Water the fern\n\n\n      twice a week']) {
        expect(roundTrip(markdown), markdown, reason: markdown);
        expect(written(read(markdown)).contains(RegExp(r' +\n')), isFalse, reason: markdown);
      }
    });

    test('a line not indented to the words ends the item', () {
      const markdown = '1. Rinse the cups\nWhy: the tea is cleaner\n1. Boil the kettle';
      expect(shapeOf(read(markdown)), [
        ['numbered', 0, 'Rinse the cups[]'], ['paragraph', 0, 'Why: the tea is cleaner[]'], ['numbered', 0, 'Boil the kettle[]'],
      ]);
      expect(roundTrip(markdown), markdown);
    });
  });

  test('a dashed sub-list under a dashed item stays dashed, a level in', () {
    const markdown = '- Garden\n  - Rake\n  - Hoe\n- Shed';
    final nodes = read(markdown);
    expect([for (final block in nodes.cast<NoteLine>()) (block.kind, block.indent)], [
      (LineKind.dashed, 0), (LineKind.dashed, 1), (LineKind.dashed, 1), (LineKind.dashed, 0),
    ]);
    expect(written(nodes), markdown);
  });
}
