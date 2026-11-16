import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../editor/shortcuts.dart';
import '../relay.dart';
import '../screens/folder.dart' show Opener;
import '../screens/note_editor.dart' show FilesPicker, Sharer;
import '../web/shell.dart';
import 'drops.dart';

final _light = brandTheme(Brightness.light);
final _dark = brandTheme(Brightness.dark);

/// What the Mac's menu bar does: each item calls the window's own action for its key, so a menu and a key do the
/// same thing.
typedef MacActions = ({VoidCallback newNote, VoidCallback find, void Function(FormatAction action) format,
  VoidCallback settings});

/// The Mac's menu bar, each item with its key. The window takes each key first, so a key never runs twice; a menu item
/// acts on a click.
List<PlatformMenuItem> macMenus(MacActions actions) {
  PlatformMenuItem item(String label, LogicalKeyboardKey key, VoidCallback onSelected) =>
    PlatformMenuItem(label: label, shortcut: SingleActivator(key, meta: true), onSelected: onSelected);
  List<PlatformMenuItem> provided(List<PlatformProvidedMenuItemType> types) => [
    for (final type in types)
      if (PlatformProvidedMenuItem.hasMenu(type)) PlatformProvidedMenuItem(type: type),
  ];
  // Flutter refuses an empty group or menu, and the system's own items exist only on the Mac.
  List<PlatformMenuItem> group(List<PlatformMenuItem> members) =>
    members.isEmpty ? const [] : [PlatformMenuItemGroup(members: members)];
  List<PlatformMenuItem> menu(String label, List<PlatformMenuItem> menus) =>
    menus.isEmpty ? const [] : [PlatformMenu(label: label, menus: menus)];
  return [
    ...menu('Relay Everything', [
      ...provided([PlatformProvidedMenuItemType.about]),
      ...group([item('Settings…', LogicalKeyboardKey.comma, actions.settings)]),
      ...group(provided([PlatformProvidedMenuItemType.servicesSubmenu])),
      ...group(provided([PlatformProvidedMenuItemType.hide, PlatformProvidedMenuItemType.hideOtherApplications,
        PlatformProvidedMenuItemType.showAllApplications])),
      ...provided([PlatformProvidedMenuItemType.quit]),
    ]),
    ...menu('File', [item('New Note', LogicalKeyboardKey.keyN, actions.newNote)]),
    ...menu('Edit', [
      ...group([
        item('Undo', LogicalKeyboardKey.keyZ, () => _edit(const UndoTextIntent(SelectionChangedCause.keyboard))),
        PlatformMenuItem(label: 'Redo', shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
          onSelected: () => _edit(const RedoTextIntent(SelectionChangedCause.keyboard))),
      ]),
      ...group([
        item('Cut', LogicalKeyboardKey.keyX, () => _edit(CopySelectionTextIntent.cut(SelectionChangedCause.keyboard))),
        item('Copy', LogicalKeyboardKey.keyC, () => _edit(CopySelectionTextIntent.copy)),
        item('Paste', LogicalKeyboardKey.keyV, () => _edit(const PasteTextIntent(SelectionChangedCause.keyboard))),
        item('Select All', LogicalKeyboardKey.keyA, () => _edit(const SelectAllTextIntent(SelectionChangedCause.keyboard))),
      ]),
      ...group([item('Find', LogicalKeyboardKey.keyF, actions.find)]),
    ]),
    // The same items and keys as the note page's format keys, from one list, so the two can not drift.
    ...menu('Format', [
      for (final members in formatItems)
        PlatformMenuItemGroup(members: [
          for (final format in members)
            PlatformMenuItem(label: format.label,
              shortcut: SingleActivator(format.key, meta: true, shift: format.shift, alt: format.alt),
              onSelected: () => actions.format(format.action)),
        ]),
    ]),
    ...menu('Window', provided([PlatformProvidedMenuItemType.minimizeWindow, PlatformProvidedMenuItemType.zoomWindow,
      PlatformProvidedMenuItemType.toggleFullScreen, PlatformProvidedMenuItemType.arrangeWindowsInFront])),
  ];
}

/// An *Edit* item: the same step its key takes in the field or note that has the cursor.
void _edit(Intent intent) {
  final context = primaryFocus?.context;
  if (context != null) Actions.maybeInvoke(context, intent);
}

/// The Relay Everything Mac app: the computer page's layout over the notes kept on this Mac, the Mac's menu bar, and
/// files dropped from Finder. The look follows *Appearance*, and the Mac's own setting while it is *System*.
class MacApp extends StatefulWidget {
  const MacApp({super.key, required this.relay, this.opener, this.picker, this.sharer, this.drops});

  final Relay relay;
  /// Opens a link in the person's browser; a test passes its own.
  final Opener? opener;
  final FilesPicker? picker;
  final Sharer? sharer;
  /// Files dropped on the window; Finder's drops when null.
  final Stream<List<NewFile>>? drops;

  @override
  State<MacApp> createState() => MacAppState();
}

class MacAppState extends State<MacApp> {
  final _shell = GlobalKey<WebShellState>();
  final _drops = StreamController<List<NewFile>>.broadcast();

  late final MacActions actions = (
    newNote: () => _shell.currentState?.newNote(),
    find: () => _shell.currentState?.find(),
    format: (action) => _shell.currentState?.format(action),
    settings: () => _shell.currentState?.settings(),
  );

  @override
  void dispose() {
    unawaited(_drops.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relay = widget.relay;
    return PlatformMenuBar(
      menus: macMenus(actions),
      child: ListenableBuilder(
        listenable: relay,
        builder: (context, shell) => MaterialApp(
          title: 'Relay Everything',
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: switch (relay.settings.appearance) {
            Appearance.light => ThemeMode.light,
            Appearance.dark => ThemeMode.dark,
            Appearance.system => ThemeMode.system,
          },
          home: shell,
        ),
        child: MacDropTarget(onDrop: _drops.add, child: WebShell(key: _shell, relay: relay, client: null, opener: widget.opener,
          picker: widget.picker, sharer: widget.sharer, drops: widget.drops ?? _drops.stream)),
      ),
    );
  }
}
