import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../data/files.dart';

/// The files the person drops anywhere on the page, each with its bytes. The page takes the drop, so the browser does
/// not open the file in place of the app.
Stream<List<NewFile>> fileDrops() {
  late final StreamController<List<NewFile>> drops;
  final over = ((web.DragEvent event) => event.preventDefault()).toJS;
  final drop = ((web.DragEvent event) {
    event.preventDefault();
    final list = event.dataTransfer?.files;
    if (list == null || list.length == 0) return;
    unawaited(_read([for (var i = 0; i < list.length; i++) ?list.item(i)]).then(drops.add));
  }).toJS;
  drops = StreamController<List<NewFile>>.broadcast(
    onListen: () {
      web.window.addEventListener('dragover', over);
      web.window.addEventListener('drop', drop);
    },
    onCancel: () {
      web.window.removeEventListener('dragover', over);
      web.window.removeEventListener('drop', drop);
    },
  );
  return drops.stream;
}

/// A file over the limit is not read: the note's check names it and leaves it out.
Future<List<NewFile>> _read(List<web.File> files) async => [
  for (final file in files)
    NewFile(name: file.name, size: file.size, type: file.type,
      bytes: file.size > maxFileBytes ? null : (await file.arrayBuffer().toDart).toDart.asUint8List()),
];
