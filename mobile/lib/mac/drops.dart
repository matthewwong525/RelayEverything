import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import '../data/files.dart';

/// Files dropped from Finder on the Mac's window: [onDrop] gets each drop's files, as the note takes them.
class MacDropTarget extends StatelessWidget {
  const MacDropTarget({super.key, required this.onDrop, required this.child});

  final ValueChanged<List<NewFile>> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragDone: (details) => unawaited(droppedFiles(details.files, access: _access).then(onDrop)),
    child: child,
  );

  /// A file from outside the app's own folder opens only with its bookmark, under App Sandbox. The access lasts while
  /// the app is open, so the note can still copy the file after the drop.
  static Future<void> _access(DropItem item) async {
    final bookmark = item.extraAppleBookmark;
    if (bookmark == null || bookmark.isEmpty) return;
    try {
      await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
    } on Exception {
      // The copy then says the file could not be added.
    }
  }
}

/// The files of one drop as [NewFile]s, each with its path and size. A folder is left out: a note takes files only.
/// [access] runs first for each file, such as to open it under App Sandbox.
Future<List<NewFile>> droppedFiles(List<DropItem> items, {Future<void> Function(DropItem item)? access}) async {
  final files = <NewFile>[];
  for (final item in items) {
    if (item is DropItemDirectory) continue;
    await access?.call(item);
    try {
      files.add(NewFile(path: item.path, name: item.name, size: await item.length()));
    } on Exception {
      // Gone, or not readable: nothing to add.
    }
  }
  return files;
}
