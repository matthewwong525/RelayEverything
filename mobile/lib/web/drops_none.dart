import '../data/files.dart';

/// No files are dropped outside a browser.
Stream<List<NewFile>> fileDrops() => const Stream.empty();
