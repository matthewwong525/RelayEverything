import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/attachments.dart';
import '../relay.dart';

/// Picks photos ([photos] true) or files from the phone. The app's is `file_picker`; a test passes its own.
typedef FilesPicker = Future<List<NewFile>> Function({required bool photos});

/// The phone's own picker: Photos for pictures and videos, Files for any file.
Future<List<NewFile>> pickWithPhone({required bool photos}) async {
  final picked = await FilePicker.pickFiles(type: photos ? FileType.media : FileType.any);
  return [
    for (final file in picked)
      if (file.path != null) NewFile(path: file.path!, name: file.name, size: await file.length() ?? 0),
  ];
}

/// A new note: the keyboard opens at once, and Save keeps it even with no signal. The paperclip adds photos or files.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.relay, this.picker});

  final Relay relay;
  final FilesPicker? picker;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _text = TextEditingController();
  var _files = <NewFile>[];
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _attach() async {
    final photos = await showModalBottomSheet<bool>(context: context, builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_outlined), title: const Text('Photos'), onTap: () => Navigator.pop(context, true)),
        ListTile(leading: const Icon(Icons.insert_drive_file_outlined), title: const Text('Files'),
          onTap: () => Navigator.pop(context, false)),
      ]),
    ));
    if (photos == null) return;
    final List<NewFile> picked;
    try {
      picked = await (widget.picker ?? pickWithPhone)(photos: photos);
    } on Exception {
      if (mounted) _say('The phone did not give the file. Try again.');
      return;
    }
    if (!mounted || picked.isEmpty) return;
    final check = checkFiles(_files, picked);
    setState(() => _files = check.kept);
    if (check.problem != null) _say(check.problem!);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final problem = await widget.relay.addNote(_text.text, files: _files);
    if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New note'), actions: [
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving || (_text.text.trim().isEmpty && _files.isEmpty) ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: true,
              maxLength: 20000,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What do you want to keep?', border: InputBorder.none, counterText: ''),
            ),
          ),
          if (_files.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final file in _files)
                InputChip(
                  label: Text('${file.name} · ${sizeLabel(file.size)}'),
                  deleteButtonTooltipMessage: 'Remove ${file.name}',
                  onDeleted: _saving ? null : () => setState(() => _files = [..._files]..remove(file)),
                ),
            ]),
          SafeArea(
            top: false,
            child: TextButton.icon(
              onPressed: _saving || _files.length >= maxFiles ? null : _attach,
              icon: const Icon(Icons.attach_file),
              label: const Text('Add photo or file'),
            ),
          ),
        ]),
      ),
    );
  }
}
