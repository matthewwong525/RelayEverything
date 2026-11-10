/// Files on a note kept on the phone: the app's own copy of each. `files.dart` holds what the browser shares.
library;

import 'dart:io';

import 'files.dart';
import 'store.dart';

export 'files.dart';

/// Copies a file into `attachments/<id><.ext>` under [root], the app's support folder, or moves it there when it is the
/// app's own copy. Null when it could not, or when the file is over 25 MB. A file already at its place, such as one an
/// earlier try moved before the app closed, is kept as it is.
Future<Attachment?> keepFile(String root, NewFile file, String id) async {
  final path = 'attachments/$id${extensionOf(file.name)}';
  final target = File('$root/$path');
  final source = File(file.path.startsWith('/') ? file.path : '$root/${file.path}');
  try {
    await target.parent.create(recursive: true);
    if (!await source.exists() && await target.exists()) {
      // Moved already.
    } else if (file.move) {
      try {
        await source.rename(target.path);
      } on FileSystemException {
        await source.copy(target.path);
        await source.delete();
      }
    } else {
      await source.copy(target.path);
    }
    final size = await target.length();
    if (size > maxFileBytes) {
      await target.delete();
      return null;
    }
    return Attachment(id: id, name: file.name, type: file.type, size: size, path: path);
  } on FileSystemException {
    return null;
  }
}
