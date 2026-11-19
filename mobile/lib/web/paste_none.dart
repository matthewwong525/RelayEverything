import 'package:flutter/foundation.dart' show visibleForTesting;

/// Takes a paste's [html] and [plain] words, and says whether it put them in.
typedef PasteTaker = bool Function({String? html, required String plain});

final _takers = <PasteTaker>[];

/// No browser paste comes outside a browser: only a test sends one, through [browserPaste]. The returned function
/// stops listening.
void Function() listenPastes(PasteTaker take) {
  _takers.add(take);
  return () => _takers.remove(take);
}

/// A browser's paste event with [html] and [plain], as `paste_browser.dart` hands it on, for a test of the web page's
/// paste. True when a listener put the words in.
@visibleForTesting
bool browserPaste({String? html, required String plain}) {
  for (final take in List.of(_takers)) {
    if (take(html: html, plain: plain)) return true;
  }
  return false;
}
