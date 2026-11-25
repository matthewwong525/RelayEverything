// The editor page's host: the system's web view on a phone and a Mac, a frame in the browser app.
export 'host_native.dart' if (dart.library.js_interop) 'host_frame.dart';
