import 'dart:math';

import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/editor/markdown.dart';

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
      test(name, () => expect(deltaToMarkdown(markdownToDelta(markdown)), markdown));
    }
  });

  test('reads each style as the editor draws it', () {
    final delta = markdownToDelta('# Shop\n- [ ] Eggs\n**Milk**');
    expect(delta.toJson(), [
      {'insert': 'Shop'}, {'insert': '\n', 'attributes': {'header': 1}},
      {'insert': 'Eggs'}, {'insert': '\n', 'attributes': {'list': 'unchecked'}},
      {'insert': 'Milk', 'attributes': {'bold': true}}, {'insert': '\n'},
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
      expect(deltaToMarkdown(markdownToDelta(note)), note, reason: note);
    }
  });

  /// Each letter with its styles: spaces may lose theirs, as a style's edge spaces go outside its marks.
  List<String> styled(Delta delta) => [
    for (final op in delta.toList())
      for (final char in (op.data as String).split(''))
        if (char.trim().isNotEmpty) '$char ${(op.attributes?.keys.toList() ?? [])..sort()}',
  ];

  group('italic on part of a word', () {
    Delta foobar() => Delta()..insert('foo', {'italic': true})..insert('bar\n');

    test('is written with stars and reads back as italic', () {
      expect(deltaToMarkdown(foobar()), '*foo*bar');
      expect(markdownToDelta('*foo*bar').toJson(), foobar().toJson());
      final middle = Delta()..insert('re')..insert('think', {'italic': true})..insert('ing\n');
      expect(deltaToMarkdown(middle), 're*think*ing');
      expect(markdownToDelta('re*think*ing').toJson(), middle.toJson());
    });

    test('a whole word stays with underscores, and snake_case and a bullet stay as typed', () {
      expect(deltaToMarkdown(Delta()..insert('Buy ')..insert('fresh', {'italic': true})..insert(' milk\n')), 'Buy _fresh_ milk');
      expect(markdownToDelta('snake_case_name').toJson(), [{'insert': 'snake_case_name\n'}]);
      expect(markdownToDelta('* foo*bar').toJson(), [{'insert': 'foo*bar'}, {'insert': '\n', 'attributes': {'list': 'bullet'}}]);
    });

    test('any mix of styles on any words comes back the same', () {
      final random = Random(7);
      const keys = ['bold', 'italic', 'strike', 'underline'];
      for (var round = 0; round < 3000; round++) {
        // A line that starts with spaces is indented, so each starts with a letter.
        final delta = Delta()..insert('x');
        for (var run = random.nextInt(5) + 1; run > 0; run--) {
          final words = String.fromCharCodes([for (var i = random.nextInt(4) + 1; i > 0; i--) 'ab '.codeUnitAt(random.nextInt(3))]);
          final marks = {for (final key in keys) if (random.nextInt(3) == 0) key: true};
          delta.insert(words, marks.isEmpty ? null : marks);
        }
        delta.insert('\n');
        final markdown = deltaToMarkdown(delta);
        expect(deltaToMarkdown(markdownToDelta(markdown)), markdown, reason: markdown);
        final words = [for (final op in delta.toList()) op.data as String].join();
        expect(plainText(markdown), words.substring(0, words.length - 1), reason: markdown);
        expect(styled(markdownToDelta(markdown)), styled(delta), reason: markdown);
      }
    });
  });

  test('two code blocks that touch stay two after an edit', () {
    final delta = markdownToDelta('```\none\n```\n```\ntwo\n```');
    final code = {'code-block': true};
    expect(delta, Delta()..insert('one')..insert('\n', code)..insert('\ntwo')..insert('\n', code));
    expect(deltaToMarkdown(delta), '```\none\n```\n\n```\ntwo\n```');
  });

  test('spaces at a style edge go outside its marks', () {
    final delta = Delta()..insert('Buy ')..insert('fresh ', {'bold': true})..insert('milk\n');
    expect(deltaToMarkdown(delta), 'Buy **fresh** milk');
  });

  test('a link or a colour pasted in keeps its words', () {
    final delta = Delta()..insert('site', {'link': 'https://example.com', 'color': '#f00'})..insert('\n');
    expect(deltaToMarkdown(delta), 'site');
  });

  test('with title, a first line with no style shows as a Title, and only that', () {
    expect(markdownToDelta('Shop\nEggs', title: true).toList()[1].attributes, {'header': 1});
    expect(markdownToDelta('* Shop', title: true).toList()[1].attributes, {'list': 'bullet'});
    expect(markdownToDelta('', title: true).toList().single.attributes, isNull);
  });

  test('plain text drops the marks', () {
    expect(plainText('# Shop\n- [ ] Eggs\n* **Milk**\n> <u>soon</u>'), 'Shop\nEggs\nMilk\nsoon');
    expect(plainText('snake_case 5 * 3'), 'snake_case 5 * 3');
    expect(plainText(''), '');
  });
}
