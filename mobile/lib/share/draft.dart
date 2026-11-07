import '../data/attachments.dart';

/// What another app shared, as the share card shows it before *Save*. The iPhone's share extension keeps the same
/// rules in Swift (`ios/ShareExtension/ShareNote.swift`); both are checked against the same six cases.
class ShareDraft {
  const ShareDraft._({this.text, this.title, this.url, this.files = const [], this.leftOut});

  /// Builds a draft from what the other app gave: [text], a [subject] (a page's title, or an email's subject), a
  /// [url], and [files]. A text that is only a web address is the link: Android browsers share a page that way.
  /// Files past the tenth, or over 25 MB, are left out, with the words to show in [leftOut].
  factory ShareDraft.of({String? text, String? subject, String? url, List<NewFile> files = const []}) {
    var body = _clean(text);
    var link = _clean(url);
    if (link == null && body != null && _webAddress.hasMatch(body)) {
      link = body;
      body = null;
    }
    // A link the text already holds is not written a second time.
    if (link != null && body != null && body.contains(link)) link = null;
    final title = link == null ? null : _clean(subject);
    final check = checkFiles(const [], files);
    return ShareDraft._(text: body, title: title == link ? null : title, url: link, files: check.kept,
      leftOut: check.problem);
  }

  /// The shared words, other than a link.
  final String? text;
  /// The page's title, with a link only.
  final String? title;
  final String? url;
  /// The files the note gets: at most 10, each at most 25 MB.
  final List<NewFile> files;
  /// What was left out, such as *A note holds up to 10 files. 2 files were not added.*; null when nothing was.
  final String? leftOut;

  /// True when the draft has something to keep, other than the person's own words.
  bool get hasItems => text != null || url != null || files.isNotEmpty;

  /// *Save* is on only when the note gets something: words, shared text, a link or a file.
  bool canSave(String words) => words.trim().isNotEmpty || hasItems;

  /// The note's text: the person's words, then the shared text, then the link as its title and address, one per line.
  String noteText(String words) => [words.trim(), ?text, ?title, ?url].where((part) => part.isNotEmpty).join('\n');

  static final _webAddress = RegExp(r'^https?://\S+$');

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
