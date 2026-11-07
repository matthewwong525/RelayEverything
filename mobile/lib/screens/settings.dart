import 'package:flutter/material.dart';

import '../relay.dart';
import '../voice/model.dart' show megabytes;
import 'connect.dart';

String _two(int value) => value.toString().padLeft(2, '0');

/// What a Settings line says about sending: *Sent 14:05 · 3 waiting*, with the date when it was not today.
String sentLine(SendState state, String what, DateTime now) {
  final at = state.at;
  final waiting = switch (state.waiting) { 0 => 'none waiting', 1 => '1 $what waiting', final n => '$n ${what}s waiting' };
  if (at == null) return 'Not sent yet · $waiting';
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  final today = at.year == now.year && at.month == now.month && at.day == now.day;
  return 'Sent ${today ? time : '${at.day}/${at.month} $time'} · $waiting';
}

/// Each switch acts at once and asks for its permission only when turned on. Sending is off until the person turns it
/// on; health, the calendar and location history sit under it and work only with it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.relay, this.scanner});

  final Relay relay;
  final Scanner? scanner;

  Future<void> _apply(BuildContext context, Future<String?> change) async {
    final problem = await change;
    if (problem != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) {
          final settings = relay.settings;
          final sending = settings.sending;
          return ListView(children: [
            SwitchListTile(
              title: const Text('Pin notes to where I am'),
              subtitle: const Text('Each typed note keeps where you were. It works with no signal.'),
              value: settings.pinNotes,
              onChanged: (on) => _apply(context, relay.setPinNotes(on)),
            ),
            const Divider(),
            _VoiceSection(relay: relay),
            const Divider(),
            SwitchListTile(
              title: const Text('Send to Relay Everything'),
              subtitle: const Text('Your server can pass notes to your own database and your AI. '
                'Off: nothing leaves this phone.'),
              value: sending,
              onChanged: (on) => on ? _startSending(context) : _stopSending(context),
            ),
            SwitchListTile(
              title: const Text('Health: steps, heart rate, sleep and more'),
              subtitle: Text(settings.health ? sentLine(relay.healthSent, 'reading', DateTime.now())
                : 'Sends the last 90 days, then new readings about each hour, also while the app is closed. You choose each '
                  'type in the phone\'s health permission.'),
              value: settings.health,
              onChanged: sending ? (on) => _apply(context, relay.setHealth(on)) : null,
            ),
            SwitchListTile(
              title: const Text('Calendar'),
              subtitle: Text(settings.calendar ? sentLine(relay.calendarSent, 'event', DateTime.now())
                : 'Sends your events from the phone\'s calendars, 90 days back and ahead. It never changes an event.'),
              value: settings.calendar,
              onChanged: sending ? (on) => _apply(context, relay.setCalendar(on)) : null,
            ),
            if (settings.calendar)
              for (final calendar in relay.calendars) SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(calendar.name),
                subtitle: calendar.account == null || calendar.account!.isEmpty ? null : Text(calendar.account!),
                value: !settings.calendarsOff.contains(calendar.id),
                onChanged: (on) => relay.setCalendarShown(calendar.id, on),
              ),
            SwitchListTile(
              title: const Text('Location history'),
              subtitle: Text(settings.history ? sentLine(relay.pointsSent, 'point', DateTime.now())
                : 'Keeps where you go, also while the app is closed, so ring notes get a place too.'),
              value: settings.history,
              onChanged: sending ? (on) => _apply(context, relay.setHistory(on)) : null,
            ),
            if (settings.history && relay.locationModes) RadioGroup<LocationMode>(
              groupValue: settings.mode,
              onChanged: (mode) { if (mode != null) _apply(context, relay.setLocationMode(mode)); },
              child: const Column(children: [
                RadioListTile(value: LocationMode.battery, title: Text('Save battery'),
                  subtitle: Text('A point at each move of about 500 m, and when you arrive or leave.')),
                RadioListTile(value: LocationMode.move, title: Text('Every 100 m'),
                  subtitle: Text('A point each 100 m, or each 5 minutes while you stay. It uses more battery.')),
              ]),
            ),
            if (relay.connected) ...[
              ListTile(
                title: const Text('Server'),
                subtitle: Text(relay.server ?? ''),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editServer(context),
              ),
              ListTile(
                title: const Text('Disconnect this phone'),
                subtitle: const Text('Removes the key from this phone and turns sending off. Your notes stay here.'),
                onTap: () => _disconnect(context),
              ),
            ],
          ]);
        },
      ),
    );
  }

  /// Connects a key the first time, then asks about the notes that never went, then turns sending on.
  Future<void> _startSending(BuildContext context) async {
    if (!relay.connected) {
      final connected = await Navigator.of(context).push(MaterialPageRoute<bool>(
        builder: (_) => ConnectScreen(relay: relay, scanner: scanner)));
      if (connected != true || !context.mounted) return;
    }
    final earlier = await relay.earlierNotes();
    var sendEarlier = false;
    if (earlier > 0) {
      if (!context.mounted) return;
      final choice = await showDialog<bool>(context: context, builder: (context) => _EarlierDialog(count: earlier));
      if (choice == null) return;
      sendEarlier = choice;
    }
    if (context.mounted) await _apply(context, relay.startSending(sendEarlier: sendEarlier));
  }

  Future<void> _stopSending(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stop sending?'),
      content: const Text('New notes stay on this phone. Notes already on your Relay Everything server stay there. Health, the calendar and location stop.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sending')),
      ],
    ));
    if (sure == true) await relay.stopSending();
  }

  Future<void> _editServer(BuildContext context) async {
    final address = await showDialog<String>(context: context, builder: (context) => ServerDialog(server: relay.server));
    if (address != null && context.mounted) await _apply(context, relay.setServer(address));
  }

  Future<void> _disconnect(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Disconnect this phone?'),
      content: const Text('Sending turns off. You need a new key to send again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
      ],
    ));
    if (sure == true) await relay.disconnect();
  }
}

/// The speech model voice notes use: where it is, its size, and *Remove* to free the space.
class _VoiceSection extends StatelessWidget {
  const _VoiceSection({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = megabytes(relay.modelBytes);
    final state = switch (relay.speechModel) {
      ModelState.ready => 'Speech model: on this phone, $size',
      ModelState.downloading => 'Speech model: getting it… ${(relay.modelProgress * 100).floor()}%',
      ModelState.failed => 'Speech model: did not download. Hold to talk on the timeline to try again.',
      _ => 'Speech model: not on this phone. Your first voice note asks to get it, $size.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        title: const Text('Voice notes'),
        subtitle: const Text('Your voice is written into words on this phone. Recordings never leave it.'),
      ),
      ListTile(
        title: Text(state, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        trailing: relay.speechModel == ModelState.ready
          ? OutlinedButton(onPressed: relay.removeSpeechModel, child: const Text('Remove'))
          : null,
      ),
    ]);
  }
}

/// Asks whether the notes kept only on this phone go too. *Only new notes* keeps no record, so the next turn-on asks
/// again.
class _EarlierDialog extends StatelessWidget {
  const _EarlierDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(count == 1 ? 'Send your earlier note too?' : 'Send your $count earlier notes too?'),
      content: Text('${count == 1 ? 'It was' : 'They were'} only on this phone. New notes go to your Relay Everything server from now on.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Only new notes')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(count == 1 ? 'Send it' : 'Send them')),
      ],
    );
  }
}
