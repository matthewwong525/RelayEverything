import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../markdown.dart' show Json;
import 'web_note.dart';

/// The editor page's place among the app's files.
const editorPage = 'assets/editor/index.html';

/// A new editor page in the system's web view.
WebNote makeWebNote() => NativeWebNote();

/// Whether this platform can show the editor page: an iPhone, an iPad, an Android phone and a Mac.
bool get webNotesWork => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android ||
  defaultTargetPlatform == TargetPlatform.macOS;

/// The editor page in WebKit on an iPhone and a Mac, and in Android's WebView. The page comes from the app's own files
/// and loads nothing else: every other address is refused, and a link the page did not catch opens in the browser.
class NativeWebNote extends WebNote {
  NativeWebNote() {
    unawaited(_start());
  }

  final controller = WebViewController();

  Future<void> _start() async {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Transparent: until the page draws, the note page's own colour shows, never a white frame.
    await controller.setBackgroundColor(const Color(0x00000000));
    await controller.addJavaScriptChannel('relayBridge', onMessageReceived: (message) => receive(message.message));
    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        if (pageMayLoad(request.url)) return NavigationDecision.navigate;
        // A link the page did not catch opens as a tap on a link does: in the browser, never in the note.
        final address = Uri.tryParse(request.url);
        if (address != null && const {'https', 'http', 'mailto'}.contains(address.scheme)) {
          receive({'is': 'open', 'address': request.url});
        }
        return NavigationDecision.prevent;
      },
      onWebResourceError: (error) {
        // WebKit stopped the page's process, as it may for memory: the page starts again.
        if (error.errorType == WebResourceErrorType.webContentProcessTerminated) gone();
      },
    ));
    await controller.loadFlutterAsset(editorPage);
  }

  /// Brings Android's keyboard up for the web view: Android shows it only for a tap (`MainActivity.kt`).
  static const _keyboard = MethodChannel('relay/web-keyboard');

  @override
  void post(Json message) {
    final focus = controller.runJavaScript(scriptFor(message));
    unawaited(focus.catchError((Object _) {}));
    if (defaultTargetPlatform == TargetPlatform.android && asksFocus(message)) {
      unawaited(focus.then((_) => _keyboard.invokeMethod<bool>('show')).catchError((Object _) => false));
    }
  }

  /// Cut, Copy and Paste from the Mac's *Edit* menu, as the system's own actions to the web view
  /// (`MainFlutterWindow.swift`): WebKit lets a page's script neither read nor write the clipboard.
  static const _clipboard = MethodChannel('relay/web-edit');

  @override
  void editItem(String action) {
    if (defaultTargetPlatform == TargetPlatform.macOS && const {'cut', 'copy', 'paste'}.contains(action)) {
      unawaited(_clipboard.invokeMethod<bool>(action).catchError((Object _) => false));
      return;
    }
    super.editItem(action);
  }

  @override
  void reloadPage() => unawaited(controller.loadFlutterAsset(editorPage));

  @override
  Widget view() => WebViewWidget(controller: controller);
}
