/// The editor page's folder among the browser app's files: Flutter serves each asset under `assets/`.
const editorFolder = 'assets/editor/';

/// The editor page, as the browser app's frame gets it: the text of `assets/editor/index.html`, with a `<base>` on
/// [folder], the editor's folder on the server, so its script, style sheet and font load from there.
///
/// The frame gets the page as its own text (`srcdoc`), never from an address that ends in `.html`: the server answers
/// `…/index.html` with a move to `…/editor/`, an address with no file name, which it answers with the app's own page.
/// A test checks that this text is the built page's.
String framePage(String folder) {
  final base = folder.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
  return editorPageText.replaceFirst('<head>\n', '<head>\n<base href="$base">\n');
}

/// The text of `mobile/editor-web/src/index.html`, which the build copies to `assets/editor/index.html`.
const editorPageText = '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>Relay Everything note</title>
<link rel="stylesheet" href="editor.css">
</head>
<body>
<div id="page">
  <div id="head"><div class="date"></div><div id="above"></div></div>
  <div id="note"></div>
  <div id="below"></div>
</div>
<script src="editor.js"></script>
</body>
</html>
''';
