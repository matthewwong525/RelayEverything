import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../markdown.dart' show Json;
import 'cover.dart';
import 'frame_page.dart';
import 'web_note.dart';

/// A new editor page in a frame of the browser app.
WebNote makeWebNote() => FrameWebNote();

/// The browser can always show the editor page.
bool get webNotesWork => true;

/// The editor page in a frame of the browser app's page. Only a message from this frame's own window is taken, and
/// messages go only to it. The frame gets the page's text with a `<base>` on the editor's folder ([framePage]), so it
/// asks the server for no `.html` address.
///
/// The frame hides itself until the page has drawn the note: the app always draws its view, as a view the app does
/// not draw never joins the browser's page, and its page never starts. While a dialog or a menu of the app lies over
/// it, the frame takes no click ([NoteCover]).
class FrameWebNote extends WebNote {
  FrameWebNote() {
    _show();
    frame
      ..title = 'Note'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    _look();
    addListener(_look);
    NoteCover.open.addListener(_look);
    ui_web.platformViewRegistry.registerViewFactory(_type, (int _) => frame);
    web.window.addEventListener('message', _listener);
  }

  void _look() {
    frame.style
      ..opacity = ready ? '1' : '0'
      ..pointerEvents = NoteCover.open.value > 0 ? 'none' : '';
  }

  static var _count = 0;
  final _type = 'relay-note-${_count++}';
  final frame = web.HTMLIFrameElement();
  late final JSFunction _listener = ((web.MessageEvent event) {
    final from = frame.contentWindow;
    if (from == null || !(event.source as JSAny?).strictEquals(from as JSAny?).toDart) return;
    final data = event.data.dartify();
    if (data is Map && data['relay'] is Map) receive(jsonDecode(jsonEncode(data['relay'])));
  }).toJS;

  @override
  void post(Json message) => frame.contentWindow?.postMessage({'relayDo': message}.jsify(), '*'.toJS);

  /// Sets the frame's page, which starts it again: the editor's folder is read from the app's own address.
  void _show() {
    final folder = Uri.parse(web.document.baseURI).resolve(ui_web.assetManager.getAssetUrl(editorFolder));
    frame.srcdoc = framePage('$folder').toJS;
  }

  @override
  void reloadPage() => _show();

  @override
  Widget view() => HtmlElementView(viewType: _type);

  @override
  void dispose() {
    NoteCover.open.removeListener(_look);
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }
}
