import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import '../voice/model.dart' show megabytes;
import 'back_to_notes.dart';
import 'connect.dart';

String _two(int value) => value.toString().padLeft(2, '0');

/// *14:05*, or *6/11 09:30* when [at] was not today.
String _when(DateTime at, DateTime now) {
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  final today = at.year == now.year && at.month == now.month && at.day == now.day;
  return today ? time : '${at.day}/${at.month} $time';
}

/// What a Settings line says about sending: *Sent 14:05 · 3 waiting*, with the date when it was not today.
String sentLine(SendState state, String what, DateTime now) {
  final at = state.at;
  final waiting = switch (state.waiting) { 0 => 'none waiting', 1 => '1 $what waiting', final n => '$n ${what}s waiting' };
  if (at == null) return 'Not sent yet · $waiting';
  return 'Sent ${_when(at, now)} · $waiting';
}

/// What Settings says about the webhook's last problem: a refused file, an answer that was not 2xx, or none.
String problemLine(WebhookProblem problem, DateTime now) {
  final at = _when(problem.at, now);
  if (problem.file != null) return '${problem.file} was too large for your receiver ($at), so it was not sent.';
  if (problem.status == null) return 'No answer from your receiver at $at. Notes wait on this phone until it answers.';
  return 'Your receiver answered ${problem.status} at $at. Notes wait on this phone until it takes them.';
}

/// The line under *Send my notes*: off, or where the phone sends.
String _placeLine(Relay relay) {
  final settings = relay.settings;
  if (!settings.sending) return 'Off: nothing leaves this phone. On: to your Relay Everything server, or to your own webhook.';
  if (settings.place == SendPlace.webhook) {
    return 'To your webhook: ${Uri.tryParse(relay.webhookAddress ?? '')?.host ?? ''}. Nothing goes to Relay Everything, '
      'so your Relay Everything page and your AI can not read it.';
  }
  return 'To Relay Everything: ${Uri.tryParse(relay.server ?? '')?.host ?? ''}. Your server can pass notes to your own '
    'database and your AI.';
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
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) {
          final settings = relay.settings;
          final sending = settings.sending;
          final danger = Theme.of(context).colorScheme.error;
          return CustomScrollView(slivers: [
            const SliverAppBar.large(leading: BackToNotes(), leadingWidth: backToNotesWidth, title: Text('Settings')),
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: [
              _Group(title: 'Notes', children: [
                SwitchListTile(
                  title: const Text('Pin notes to where I am'),
                  subtitle: const Text('Each typed note keeps where you were.'),
                  value: settings.pinNotes,
                  onChanged: (on) => _apply(context, relay.setPinNotes(on)),
                ),
              ]),
              _Group(title: 'Voice notes', children: [_VoiceRow(relay: relay)]),
              _Group(title: 'Sending', children: [
                SwitchListTile(
                  title: const Text('Send my notes'),
                  subtitle: Text(_placeLine(relay)),
                  value: sending,
                  onChanged: (on) => on ? _choosePlace(context) : _stopSending(context),
                ),
                SwitchListTile(
                  title: const Text('Health'),
                  subtitle: Text(settings.health ? sentLine(relay.healthSent, 'reading', DateTime.now())
                    : 'Steps, heart rate, sleep and more.'),
                  value: settings.health,
                  onChanged: sending ? (on) => _apply(context, relay.setHealth(on)) : null,
                ),
                SwitchListTile(
                  title: const Text('Calendar'),
                  subtitle: Text(settings.calendar ? sentLine(relay.calendarSent, 'event', DateTime.now())
                    : 'Your phone\'s calendars.'),
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
                    : 'Where you go, also while the app is closed.'),
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
                if (!sending) Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('Health, Calendar and Location history work with Send my notes on.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                if (sending) ListTile(
                  title: const Text('Where the phone sends'),
                  subtitle: Text(settings.place == SendPlace.webhook ? 'My own webhook' : 'Relay Everything'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _choosePlace(context),
                ),
                if (sending && settings.place == SendPlace.webhook) ...[
                  ListTile(
                    title: const Text('Webhook'),
                    subtitle: Text(relay.webhookAddress ?? ''),
                    trailing: TextButton(onPressed: () => _test(context), style: quietButton(context), child: const Text('Send a test')),
                  ),
                  if (relay.webhookProblem case final problem?) ListTile(
                    subtitle: Text(problemLine(problem, DateTime.now()), style: TextStyle(color: danger)),
                  ),
                ],
                if (relay.connected && settings.place == SendPlace.server) ...[
                  ListTile(
                    title: const Text('Server'),
                    subtitle: Text(relay.server ?? ''),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editServer(context),
                  ),
                  ListTile(
                    title: Text('Disconnect this phone', style: TextStyle(color: danger)),
                    subtitle: const Text('Removes the key from this phone and turns sending off. Your notes stay here.'),
                    onTap: () => _disconnect(context),
                  ),
                ],
              ]),
            ])),
          ]);
        },
      ),
    );
  }

  /// Asks where to send, and sets that place up: a key, or a webhook. Then asks about the notes that never went, and
  /// turns sending on there. With sending on already, it moves what waits to the new place.
  Future<void> _choosePlace(BuildContext context) async {
    final place = await Navigator.of(context).push(MaterialPageRoute<SendPlace>(
      builder: (_) => ConnectScreen(relay: relay, scanner: scanner)));
    if (place == null || !context.mounted) return;
    final earlier = await relay.earlierNotes();
    var sendEarlier = false;
    if (earlier > 0) {
      if (!context.mounted) return;
      final choice = await showDialog<bool>(context: context, builder: (context) => _EarlierDialog(count: earlier, place: place));
      if (choice == null) return;
      sendEarlier = choice;
    }
    if (context.mounted) await _apply(context, relay.startSending(sendEarlier: sendEarlier, place: place));
  }

  Future<void> _test(BuildContext context) async {
    final answer = await relay.testWebhook(relay.webhookAddress ?? '', relay.webhookSecret ?? '');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(answer)));
  }

  Future<void> _stopSending(BuildContext context) async {
    final there = relay.settings.place == SendPlace.webhook ? 'at your webhook' : 'on your Relay Everything server';
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stop sending?'),
      content: Text('New notes stay on this phone. Notes already $there stay there. Health, the calendar and location stop.'),
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

/// One Settings group: a small muted heading, and one card with its rows and no lines between them.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(title,
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: const FontWeight(650), color: theme.colorScheme.onSurfaceVariant))),
      Card(clipBehavior: Clip.antiAlias, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children))),
    ]);
  }
}

/// The speech model voice notes use: where it is, its size, and *Remove* to free the space. The voice never leaves
/// the phone.
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final size = megabytes(relay.modelBytes);
    final state = switch (relay.speechModel) {
      ModelState.ready => 'On this phone, $size. Your voice never leaves it.',
      ModelState.downloading => 'Getting it… ${(relay.modelProgress * 100).floor()}%',
      ModelState.failed => 'It did not download. Hold New note to try again.',
      _ => 'Not on this phone. Your first voice note asks to get it, $size.',
    };
    return ListTile(
      title: const Text('Speech model'),
      subtitle: Text(state),
      trailing: relay.speechModel == ModelState.ready
        ? TextButton(onPressed: relay.removeSpeechModel, style: quietButton(context), child: const Text('Remove'))
        : null,
    );
  }
}

/// Asks whether the notes kept only on this phone go too. *Only new notes* keeps no record, so the next turn-on asks
/// again.
class _EarlierDialog extends StatelessWidget {
  const _EarlierDialog({required this.count, required this.place});

  final int count;
  final SendPlace place;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(count == 1 ? 'Send your earlier note too?' : 'Send your $count earlier notes too?'),
      content: Text('${count == 1 ? 'It was' : 'They were'} only on this phone. New notes go to '
        '${place == SendPlace.webhook ? 'your webhook' : 'your Relay Everything server'} from now on.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Only new notes')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(count == 1 ? 'Send it' : 'Send them')),
      ],
    );
  }
}
