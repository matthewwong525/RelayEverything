import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Takes a paste's [html] and [plain] words, and says whether it put them in.
typedef PasteTaker = bool Function({String? html, required String plain});

/// Hands each paste on the page to [take], with the clipboard's HTML and plain words. When [take] puts them in, the
/// browser does not also paste its plain words. The browser shows no question: the paste event carries the words.
/// The returned function stops listening.
void Function() listenPastes(PasteTaker take) {
  final listener = ((web.ClipboardEvent event) {
    final data = event.clipboardData;
    if (data == null) return;
    final html = data.getData('text/html');
    if (take(html: html.isEmpty ? null : html, plain: data.getData('text/plain'))) event.preventDefault();
  }).toJS;
  // Before the page's own text field reads the paste.
  web.document.addEventListener('paste', listener, web.AddEventListenerOptions(capture: true));
  return () => web.document.removeEventListener('paste', listener, web.EventListenerOptions(capture: true));
}
