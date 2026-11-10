import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Runs [run] as the page closes, reloads or goes to another address. Only a send that needs no answer can go then.
void onPageClose(void Function() run) => web.window.addEventListener('pagehide', ((web.Event _) => run()).toJS);

/// Sends a change as the page closes: the browser keeps the request going after the page is gone, with the page's own
/// sign-in cookie and Origin. No answer comes back, so nothing can show whether it went.
void sendAsPageCloses(String method, Uri address, [String? json]) {
  web.window.fetch(address.toString().toJS, web.RequestInit(
    method: method,
    keepalive: true,
    credentials: 'same-origin',
    headers: {'Accept': 'application/json', if (json != null) 'Content-Type': 'application/json'}.jsify()! as web.HeadersInit,
    body: json?.toJS,
  )).toDart.ignore();
}
