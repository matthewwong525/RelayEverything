import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/editor/markdown.dart' show Json, LineKind, highlightColours;
import 'package:relay_app/editor/web_note/frame_page.dart';
import 'package:relay_app/editor/web_note/pictures.dart';
import 'package:relay_app/editor/web_note/web_note.dart';
import 'package:relay_app/editor/web_note/web_note_pool.dart';
import 'package:relay_app/screens/note_editor.dart' show cssColour, editorThemeOf;

/// A page with no web view: it keeps each message it was sent, and how many times it started again.
class _Page extends WebNote {
  final posts = <Json>[];
  var reloads = 0;

  @override
  void post(Json message) => posts.add(message);

  @override
  void reloadPage() => reloads++;

  @override
  Widget view() => const SizedBox();
}

/// A 1 × 1 PNG.
final _dot = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  group('the messages', () {
    test('a message goes to the page as one JSON text, so no letter in a note can break out of the script', () {
      const words = "it's \"quoted\" </script> \\ \n and  ";
      final script = scriptFor({'do': 'run', 'action': 'link', 'value': words});
      expect(script, startsWith('window.relayReceive("'));
      final inner = script.substring('window.relayReceive('.length, script.length - 1);
      expect(jsonDecode(jsonDecode(inner) as String), {'do': 'run', 'action': 'link', 'value': words});
    });

    test('a web view loads only the editor page, never a link', () {
      expect(pageMayLoad('file:///private/var/app/Runner.app/Frameworks/App.framework/flutter_assets/assets/editor/index.html'),
        isTrue);
      expect(pageMayLoad('about:blank'), isTrue);
      for (final url in ['https://example.com', 'file:///etc/passwd', 'javascript:alert(1)', 'mailto:sam@example.com',
          'https://example.com/assets/editor/index.html', '']) {
        expect(pageMayLoad(url), isFalse, reason: url);
      }
    });

    test('a load with focus and a run of focus ask for the keyboard; nothing else does', () {
      expect(asksFocus({'do': 'load', 'focus': true}), isTrue);
      expect(asksFocus({'do': 'run', 'action': 'focus', 'value': 'new-line'}), isTrue);
      expect(asksFocus({'do': 'load', 'focus': false}), isFalse);
      expect(asksFocus({'do': 'run', 'action': 'bold'}), isFalse);
      expect(asksFocus({'do': 'theme'}), isFalse);
    });

    test('messages wait until the page starts, and a load drops what waited before it', () {
      final page = _Page()
        ..run('bold')
        ..load(doc: const {'type': 'doc'}, theme: const {}, focus: true)
        ..run('italic');
      expect(page.posts, isEmpty);
      page.receive({'is': 'boot'});
      expect([for (final message in page.posts) message['do']], ['load', 'run']);
      expect(page.posts.last, {'do': 'run', 'action': 'italic'});
      expect([page.booted, page.ready], [true, false]);
      page.receive('{"is": "ready", "ms": 40}');
      expect([page.ready, page.loadMs], [true, 40]);
      page.dispose();
    });

    test('the page\'s state, its document and its other messages come in', () {
      final page = _Page();
      final others = <Json>[];
      page
        ..onMessage = others.add
        ..receive({'is': 'boot'})
        ..receive({'is': 'state', 'marks': ['bold'], 'kind': 'header2', 'focus': true, 'empty': false,
          'found': {'count': 3, 'index': 1}})
        ..receive({'is': 'changed', 'doc': {'type': 'doc', 'content': <Object>[]}})
        ..receive({'is': 'open', 'address': 'https://example.com'})
        ..receive('not JSON')
        ..receive(7);
      expect([page.state.marks, page.state.kind, page.state.focus, page.state.empty, page.state.found],
        [{'bold'}, LineKind.header2, true, false, (count: 3, index: 1)]);
      expect(page.doc, {'type': 'doc', 'content': <Object>[]});
      expect([for (final message in others) message['is']], ['changed', 'open']);
      page.dispose();
    });

    test('a page with the keyboard counts as typing, until it loses it or goes', () {
      final page = _Page()..receive({'is': 'boot'});
      expect(WebNote.typing, isFalse);
      page.receive({'is': 'state', 'focus': true});
      expect(WebNote.typing, isTrue);
      page.receive({'is': 'state', 'focus': false});
      expect(WebNote.typing, isFalse);
      page.receive({'is': 'state', 'focus': true});
      page.dispose();
      expect(WebNote.typing, isFalse);
    });

    test('a page the system closed starts again with the last words, and with no keyboard', () {
      final page = _Page()
        ..load(doc: const {'type': 'doc', 'content': <Object>[]}, theme: const {}, focus: true)
        ..receive({'is': 'boot'})
        ..receive({'is': 'ready'})
        ..receive({'is': 'state', 'focus': true});
      final typed = {'type': 'doc', 'content': [{'type': 'paragraph', 'content': [{'type': 'text', 'text': 'Milk'}]}]};
      page.receive({'is': 'changed', 'doc': typed});
      page.posts.clear();
      page.gone();
      expect([page.reloads, page.booted, page.ready, WebNote.typing], [1, false, false, false]);
      expect(page.posts, isEmpty, reason: 'it waits for the page to start');
      page.receive({'is': 'boot'});
      expect(page.posts.single['do'], 'load');
      expect([page.posts.single['doc'], page.posts.single['focus']], [typed, false]);
      page.dispose();
    });

    test('a page that starts again gets each file, setting and lock sent after the first load', () {
      final page = _Page()
        ..load(doc: const {'type': 'doc', 'content': <Object>[]}, theme: const {'ink': 'black'},
          files: const {'a': {'kind': 'file', 'name': 'a.pdf', 'ready': false}},
          head: const {'date': 'Today', 'above': <String>[], 'below': <String>[]}, placeholder: 'Old',
          appKeys: const ['new-note', 'find'])
        ..receive({'is': 'boot'})
        ..receive({'is': 'ready'})
        ..send({'do': 'files', 'files': {'a': {'kind': 'file', 'name': 'a.pdf', 'ready': true}, 'b': {'kind': 'picture'}}})
        ..send({'do': 'head', 'head': {'below': ['head:0']}})
        ..send({'do': 'theme', 'theme': {'ink': 'white'}})
        ..send({'do': 'bottom', 'bottom': 40})
        ..send({'do': 'highlight', 'colour': 'green'})
        ..send({'do': 'appKeys', 'appKeys': ['new-note']})
        ..run('editable', false)
        ..run('placeholder', 'Add notes…');
      Json again() => page.posts.lastWhere((message) => message['do'] == 'load');
      void check(String how) {
        final load = again();
        expect(load['files'], {'a': {'kind': 'file', 'name': 'a.pdf', 'ready': true}, 'b': {'kind': 'picture'}},
          reason: how);
        expect(load['head'], {'date': 'Today', 'above': <String>[], 'below': ['head:0']}, reason: how);
        expect([load['theme'], load['bottom'], load['highlight'], load['appKeys'], load['editable'], load['placeholder']],
          [{'ink': 'white'}, 40, 'green', ['new-note'], false, 'Add notes…'], reason: how);
      }

      page
        ..posts.clear()
        ..gone()
        ..receive({'is': 'boot'});
      expect([page.reloads, page.posts.length], [1, 1]);
      check('after the system closed it');

      // A page that loads again by itself, as a frame moved in the browser's page does, starts again with no `gone`.
      page
        ..receive({'is': 'ready'})
        ..receive({'is': 'state', 'focus': true})
        ..posts.clear()
        ..receive({'is': 'boot'});
      expect([page.reloads, page.posts.length, page.ready, WebNote.typing], [1, 1, false, false]);
      check('after it started again by itself');
      page.dispose();
    });

    test('an Edit item is a run in the page', () {
      final page = _Page()
        ..receive({'is': 'boot'})
        ..editItem('copy')
        ..editItem('select-all');
      expect(page.posts, [{'do': 'run', 'action': 'copy'}, {'do': 'run', 'action': 'select-all'}]);
      page.dispose();
    });
  });

  group("the browser's frame", () {
    test('gets the built page as its own text, with a base on the editor folder', () {
      const folder = 'https://relay.example.com/apps/relay/assets/assets/editor/';
      final built = File('assets/editor/index.html').readAsStringSync();
      expect(editorPageText, built, reason: 'the frame shows the page the build wrote');
      expect(framePage(folder), built.replaceFirst('<head>\n', '<head>\n<base href="$folder">\n'));
    });

    test('never asks for an address that ends in .html, which the server moves to the app\'s own page', () {
      final addresses = RegExp(r'''(?:href|src)="([^"]*)"''').allMatches(framePage('https://relay.example.com/a/'))
        .map((match) => match[1]!).toList();
      expect(addresses, ['https://relay.example.com/a/', 'editor.css', 'editor.js']);
      expect(addresses.where((address) => address.endsWith('.html')), isEmpty);
      final host = File('lib/editor/web_note/host_frame.dart').readAsStringSync();
      expect(RegExp(r'''['"][^'"]*\.html['"]''').hasMatch(host), isFalse, reason: 'the frame host names no .html address');
      expect(host, contains('srcdoc'));
      expect(host, isNot(contains('..src')));
    });
  });

  group('the pool', () {
    test('a note takes a spare that started, a new spare starts in its place, and a page given back goes', () {
      final pool = WebNotePool(_Page.new, spares: 2)..warm();
      expect([pool.made.length, pool.waiting], [2, 2]);
      pool.made[1].receive({'is': 'boot'});
      final taken = pool.take();
      expect(taken, same(pool.made[1]), reason: 'the page that started goes first');
      expect([pool.made.length, pool.waiting], [3, 2]);
      pool.giveBack(taken);
      expect(pool.made, isNot(contains(taken)));
      expect(() => taken.addListener(() {}), throwsFlutterError, reason: 'the page was let go');
    });

    test('with no spare, each note makes its own page', () {
      final pool = WebNotePool(_Page.new, spares: 0)..warm();
      expect(pool.waiting, 0);
      final first = pool.take();
      final second = pool.take();
      expect([first == second, pool.made.length, pool.waiting], [false, 2, 0]);
    });
  });

  group('the page\'s look', () {
    test('a colour goes to the page as CSS', () {
      expect(cssColour(const Color(0xFF102030)), 'rgba(16, 32, 48, 1.000)');
      expect(cssColour(const Color(0x80FFFFFF)), 'rgba(255, 255, 255, 0.502)');
    });

    for (final brightness in Brightness.values) {
      testWidgets('the page takes the app\'s ${brightness.name} colours', (tester) async {
        late Map<String, String> theme;
        await tester.pumpWidget(MaterialApp(theme: brandTheme(brightness), home: Builder(builder: (context) {
          theme = editorThemeOf(context);
          return const SizedBox();
        })));
        final brand = brightness == Brightness.dark ? BrandColors.dark : BrandColors.light;
        expect([theme['scheme'], theme['ink'], theme['paper']],
          [brightness.name, cssColour(brand.ink), cssColour(brand.paper)]);
        expect(theme.keys, containsAll([for (final colour in highlightColours) 'hl-$colour']));
      });
    }

    testWidgets('a small picture goes to the page as it is; any other goes as a PNG; one the phone cannot read is none',
        (tester) async {
      await tester.runAsync(() async {
        expect(await pictureSourceOf(_dot, 'image/png'), 'data:image/png;base64,${base64Encode(_dot)}');
        expect(await pictureSourceOf(_dot, 'image/heic'), startsWith('data:image/png;base64,'));
        expect(await pictureSourceOf(Uint8List.fromList([1, 2, 3]), 'image/heic'), isNull);
      });
    });
  });
}
