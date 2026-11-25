// The links in a note's words. The editor page shows each web address in the words as a link to itself, and words
// linked to another address keep their link. The Markdown writer writes an address linked to itself as the bare
// address, so marking links never changes the stored words.

/// A web address in a note's words: `https://…`, `http://…` or `www.…`, up to a space, less the stop or bracket that
/// ends a sentence. The editor page finds addresses by the same rule.
final _webAddress = RegExp(r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);
final _endPunctuation = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// A link's own scheme, such as `https:` or `mailto:`; `www.` has none.
final linkScheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);

/// Each web address in [words], with where it starts.
Iterable<({int start, String address})> linkRanges(String words) sync* {
  for (final match in _webAddress.allMatches(words)) {
    final address = match[0]!.replaceFirst(_endPunctuation, '');
    if (address.contains('.') && !address.endsWith('://')) yield (start: match.start, address: address);
  }
}

/// The address a person typed in the *Link* box, as the link keeps it: `example.com` gains `https://`, and an address
/// with its own scheme, such as `mailto:`, stays. Null for words that are no address.
String? linkAddressOf(String typed) {
  final words = typed.trim();
  if (words.isEmpty || words.contains(RegExp(r'\s'))) return null;
  if (linkScheme.hasMatch(words)) return words;
  return words.contains('.') ? 'https://$words' : null;
}

/// The address a link opens: one with its own scheme, such as `mailto:`, as it is, and `www.…` on the web. Null when
/// it is no address.
Uri? linkUri(String link) => Uri.tryParse(linkScheme.hasMatch(link) ? link : 'https://$link');
