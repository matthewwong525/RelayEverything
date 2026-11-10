import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'hold_to_talk.dart' show clockOf;

/// A picture of a note: the app's copy on the phone, or the person's space's file route in the browser. [cacheWidth] keeps
/// a small picture small in memory.
class EntryImage extends StatelessWidget {
  const EntryImage({super.key, required this.file, this.width, this.height, this.cacheWidth, required this.fallback});

  final EntryFile file;
  final double? width;
  final double? height;
  final int? cacheWidth;
  /// Shows when the picture does not load.
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    Widget failed(BuildContext context, Object _, StackTrace? _) => fallback;
    if (file.onPhone) {
      return Image.file(File(file.path), width: width, height: height, fit: BoxFit.cover, cacheWidth: cacheWidth,
        errorBuilder: failed);
    }
    final url = file.url;
    if (url == null) return fallback;
    return Image.network(url, width: width, height: height, fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: failed);
  }
}

/// A picture, full width; a tap opens it.
class NotePicture extends StatelessWidget {
  const NotePicture({super.key, required this.file, required this.relay});

  final EntryFile file;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Tooltip(
      message: file.name,
      child: InkWell(
        onTap: () => relay.openFile(file),
        borderRadius: BorderRadius.circular(14),
        // The height holds the place while the picture loads.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 180), child: ColoredBox(color: brand.accentSoft,
            child: EntryImage(file: file, width: double.infinity, cacheWidth: 1080,
              fallback: Container(height: 180, color: brand.accentSoft, child: Icon(CupertinoIcons.photo, color: brand.muted))))),
        ),
      ),
    );
  }
}

/// Any other file, or one not on the phone yet: its name and size in a card row; a tap downloads it if needed, then
/// opens it. In the browser a tap opens the file in a new tab.
class NoteFileRow extends StatelessWidget {
  const NoteFileRow({super.key, required this.file, required this.relay});

  final EntryFile file;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => relay.openFile(file),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(spacing: 10, children: [
            Icon(file.ready ? CupertinoIcons.doc : CupertinoIcons.cloud_download, size: 20, color: brand.muted),
            Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
            Text([if (file.size > 0) sizeLabel(file.size), if (!file.ready) 'Download'].join(' · '),
              style: TextStyle(fontSize: 13, color: brand.muted)),
          ]),
        ),
      ),
    );
  }
}

/// *Play* for a voice note's recording, as a quiet card row with its length.
class PlayRow extends StatelessWidget {
  const PlayRow({super.key, required this.length, required this.onPlay});

  final Duration? length;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          child: Row(spacing: 12, children: [
            DecoratedBox(decoration: BoxDecoration(color: brand.paper, shape: BoxShape.circle),
              child: SizedBox.square(dimension: 40, child: Icon(CupertinoIcons.play_fill, color: brand.ink))),
            const Expanded(child: Text('Play', style: TextStyle(fontWeight: FontWeight(650)))),
            if (length != null) Text(clockOf(length!), style: TextStyle(fontSize: 13, color: brand.muted)),
          ]),
        ),
      ),
    );
  }
}
