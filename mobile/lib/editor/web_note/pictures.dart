import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Picture types every web view shows as they are.
const _shownAsIs = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'};

/// The largest picture that goes to the editor page as it is: a larger one goes at the width the page shows.
const _largestAsIs = 1536 * 1024;

/// A picture on the phone as a `data:` address the editor page can show: the web view may read no file of the phone.
/// A small JPEG, PNG, GIF or WebP goes as it is; any other, such as a large photo or a HEIC, goes as a PNG at most
/// [width] pixels wide. Null when the phone can not read it.
Future<String?> pictureSource(String path, String type, {int width = 1080}) async {
  try {
    final bytes = await File(path).readAsBytes();
    return await pictureSourceOf(bytes, type, width: width);
  } on Object {
    return null;
  }
}

/// [pictureSource] for bytes already read.
Future<String?> pictureSourceOf(Uint8List bytes, String type, {int width = 1080}) async {
  if (bytes.length <= _largestAsIs && _shownAsIs.contains(type)) return 'data:$type;base64,${base64Encode(bytes)}';
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec(targetWidth: min(width, descriptor.width));
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return png == null ? null : 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
  } on Object {
    return null;
  }
}
