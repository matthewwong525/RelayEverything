/// Files on a note: the limits, the names the app shows, and the content type the server keeps.
library;

import 'dart:io';

import 'store.dart';

/// A note holds up to this many files.
const maxFiles = 10;

/// Each file is up to 25 MB, the size the server takes.
const maxFileBytes = 25 * 1024 * 1024;

/// A file the person picked, or one a shortcut gave, before the app keeps its own copy.
class NewFile {
  const NewFile({required this.path, required this.name, required this.size, this._type, this.move = false});

  /// Where the file is now, as a full path.
  final String path;
  final String name;
  final int size;
  final String? _type;

  /// True when the file is the app's own copy, such as one a shortcut gave: the app moves it, and copies nothing.
  final bool move;

  /// The content type, from the giver or else from the name.
  String get type => _type == null || _type.isEmpty ? typeOf(name) : _type;
}

/// What a check of picked files keeps, and the words to show for the files it leaves out.
class FilesCheck {
  const FilesCheck(this.kept, this.problem);

  final List<NewFile> kept;
  final String? problem;
}

/// Adds [picked] to [current] up to the limits: a file over 25 MB, or one past the tenth with the note's [already]
/// kept files, is left out with a message, and the rest are kept. The paperclip and Shortcuts both use it.
FilesCheck checkFiles(List<NewFile> current, List<NewFile> picked, {int already = 0}) {
  final kept = [...current];
  final tooBig = <String>[];
  var tooMany = 0;
  for (final file in picked) {
    if (file.size > maxFileBytes) {
      tooBig.add(file.name);
    } else if (already + kept.length >= maxFiles) {
      tooMany++;
    } else {
      kept.add(file);
    }
  }
  final problems = [
    if (tooBig.length == 1) '${tooBig.single} is over 25 MB, so it was not added.',
    if (tooBig.length > 1) '${tooBig.length} files are over 25 MB, so they were not added.',
    if (tooMany > 0) 'A note holds up to $maxFiles files. $tooMany ${tooMany == 1 ? 'file was' : 'files were'} not added.',
  ];
  return FilesCheck(kept, problems.isEmpty ? null : problems.join(' '));
}

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

/// 512 B, 240 KB, 1.2 MB.
String sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final megabytes = bytes / (1024 * 1024);
  return '${megabytes < 10 ? megabytes.toStringAsFixed(1) : megabytes.round()} MB';
}

/// A file's extension, such as `.pdf`, when it is short and plain; else empty. The app's copy keeps it, so the phone
/// knows which app opens the file.
String extensionOf(String name) {
  final match = RegExp(r'\.[A-Za-z0-9]{1,8}$').firstMatch(name);
  return match == null ? '' : match[0]!.toLowerCase();
}

const _types = {
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.gif': 'image/gif', '.webp': 'image/webp',
  '.heic': 'image/heic', '.heif': 'image/heif', '.bmp': 'image/bmp', '.tif': 'image/tiff', '.tiff': 'image/tiff',
  '.svg': 'image/svg+xml',
  '.pdf': 'application/pdf', '.txt': 'text/plain', '.md': 'text/markdown', '.csv': 'text/csv', '.json': 'application/json',
  '.html': 'text/html', '.htm': 'text/html', '.rtf': 'application/rtf', '.zip': 'application/zip',
  '.doc': 'application/msword', '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel', '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint', '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.wav': 'audio/wav', '.aac': 'audio/aac',
  '.mp4': 'video/mp4', '.mov': 'video/quicktime', '.m4v': 'video/x-m4v', '.webm': 'video/webm',
};

/// The content type for a file's name, or `application/octet-stream` when the name does not say.
String typeOf(String name) => _types[extensionOf(name)] ?? 'application/octet-stream';
