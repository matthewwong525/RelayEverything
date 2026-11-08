import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../data/connection.dart' show defaultServer;
import '../relay.dart';
import 'back_to.dart';
import 'connect.dart';

/// Opens an address in the phone's own browser, and says if it did.
typedef Opener = Future<bool> Function(Uri address);

Future<bool> openInBrowser(Uri address) async {
  try {
    return await launchUrl(address, mode: LaunchMode.externalApplication);
  } on Exception {
    return false;
  }
}

/// What the person picked when turning photos off.
enum _PhotosChoice { openPage, stop }

String _two(int value) => value.toString().padLeft(2, '0');

/// *14:05*, or *6/11 09:30* when [at] was not today.
String _when(DateTime at, DateTime now) {
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  final today = at.year == now.year && at.month == now.month && at.day == now.day;
  return today ? time : '${at.day}/${at.month} $time';
}

/// What a folder's switch says about sending: *Sent 14:05 · 3 waiting*, with the date when it was not today.
String sentLine(SendState state, String what, DateTime now) {
  final at = state.at;
  final waiting = switch (state.waiting) { 0 => 'none waiting', 1 => '1 $what waiting', final n => '$n ${what}s waiting' };
  if (at == null) return 'Not sent yet · $waiting';
  return 'Sent ${_when(at, now)} · $waiting';
}

/// The short form a Home row shows: *Sent 14:05*, and *3 waiting* only when some wait.
String _sentShort(SendState state, DateTime now) =>
  [state.at == null ? 'Not sent yet' : 'Sent ${_when(state.at!, now)}', if (state.waiting > 0) '${state.waiting} waiting'].join(' · ');

/// The *Location* row on Home: *Off*, or *Save battery · Sent 14:05*. Android has one mode, so it names none.
String locationLine(Relay relay, DateTime now) {
  if (!relay.settings.history) return 'Off';
  final mode = relay.settings.mode == LocationMode.battery ? 'Save battery' : 'Every 100 m';
  return [if (relay.locationModes) mode, _sentShort(relay.pointsSent, now)].join(' · ');
}

/// The *Health* row on Home: *Off*, or *Sent 14:02 · 3 waiting*.
String healthLine(Relay relay, DateTime now) => relay.settings.health ? _sentShort(relay.healthSent, now) : 'Off';

/// The *Calendar* row on Home: *Off*, or *2 calendars · Sent 13:40*.
String calendarLine(Relay relay, DateTime now) {
  if (!relay.settings.calendar) return 'Off';
  final on = relay.calendars.where((calendar) => !relay.settings.calendarsOff.contains(calendar.id)).length;
  return [if (relay.calendars.isNotEmpty) on == 1 ? '1 calendar' : '$on calendars', _sentShort(relay.calendarSent, now)].join(' · ');
}

/// The *Photos* row on Home: *Off*, or *On · Wi-Fi only* until mobile data is allowed too.
String photosLine(Relay relay) {
  final settings = relay.settings;
  if (!settings.photos) return 'Off';
  return settings.photosOnMobileData ? 'On · Wi-Fi and mobile data' : 'On · Wi-Fi only';
}

String _hostOf(String? address) => Uri.tryParse(address ?? '')?.host ?? '';

/// The *Sending* row on Home: off, or where the phone sends.
String sendingLine(Relay relay) {
  final settings = relay.settings;
  if (!settings.sending) return 'Off: nothing leaves this phone';
  return settings.place == SendPlace.webhook ? 'To your webhook · ${_hostOf(relay.webhookAddress)}'
    : 'To Relay Everything · ${_hostOf(relay.server)}';
}

/// What the Sending page says about the webhook's last problem: a refused file, an answer that was not 2xx, or none.
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
    return 'To your webhook: ${_hostOf(relay.webhookAddress)}. Nothing goes to Relay Everything, '
      'so your Relay Everything page and your AI can not read it.';
  }
  return 'To Relay Everything: ${_hostOf(relay.server)}. Your server can pass notes to your own database and your AI.';
}

/// Runs a change and shows why it could not be, if it could not.
Future<void> apply(BuildContext context, Future<String?> change) async {
  final problem = await change;
  if (problem != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
}

/// Asks where to send, and sets that place up: a key, or a webhook. Then asks about the notes that never went, and
/// turns sending on there. With sending on already, it moves what waits to the new place. *Send my notes*, *Turn on
/// sending* and a tap on *AI apps* or *Webhooks* while signed out all start here.
Future<void> choosePlace(BuildContext context, Relay relay, Scanner? scanner) async {
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
  if (context.mounted) await apply(context, relay.startSending(sendEarlier: sendEarlier, place: place));
}

/// A page opened from Home: *‹ Home*, a large title, and its groups. Each switch acts at once and asks for its
/// permission only when turned on.
class _FolderPage extends StatelessWidget {
  const _FolderPage({required this.relay, required this.title, required this.groups});

  final Relay relay;
  final String title;
  final List<Widget> Function(BuildContext context) groups;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) => CustomScrollView(slivers: [
          SliverAppBar.large(leading: const BackTo('Home'), leadingWidth: BackTo.widthOf('Home'), title: Text(title)),
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: groups(context))),
        ]),
      ),
    );
  }
}

/// With sending off: what the folder needs, and the one button that turns sending on, in the same steps as *Send my
/// notes*.
class _NeedsSending extends StatelessWidget {
  const _NeedsSending({required this.relay, required this.what, this.scanner});

  final Relay relay;
  final String what;
  final Scanner? scanner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('$what works with sending on. Nothing leaves this phone until you turn it on.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        FilledButton(onPressed: () => choosePlace(context, relay, scanner), child: const Text('Turn on sending')),
      ]),
    );
  }
}

/// *Location*: the location history switch, its send state, and on iPhone how often it keeps a point.
class LocationPage extends StatelessWidget {
  const LocationPage({super.key, required this.relay, this.scanner});

  final Relay relay;
  final Scanner? scanner;

  @override
  Widget build(BuildContext context) {
    return _FolderPage(relay: relay, title: 'Location', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [SwitchListTile(
          title: const Text('Location history'),
          subtitle: Text(settings.history ? sentLine(relay.pointsSent, 'point', DateTime.now())
            : 'Where you go, also while the app is closed.'),
          value: settings.history,
          onChanged: settings.sending ? (on) => apply(context, relay.setHistory(on)) : null,
        )]),
        if (settings.history && relay.locationModes) Group(title: 'How often', children: [RadioGroup<LocationMode>(
          groupValue: settings.mode,
          onChanged: (mode) { if (mode != null) apply(context, relay.setLocationMode(mode)); },
          child: const Column(children: [
            RadioListTile(value: LocationMode.battery, title: Text('Save battery'),
              subtitle: Text('A point at each move of about 500 m, and when you arrive or leave.')),
            RadioListTile(value: LocationMode.move, title: Text('Every 100 m'),
              subtitle: Text('A point each 100 m, or each 5 minutes while you stay. It uses more battery.')),
          ]),
        )]),
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Location history', scanner: scanner),
      ];
    });
  }
}

/// *Health*: the switch for steps, heart rate, sleep and more, and when they last went.
class HealthPage extends StatelessWidget {
  const HealthPage({super.key, required this.relay, this.scanner});

  final Relay relay;
  final Scanner? scanner;

  @override
  Widget build(BuildContext context) {
    return _FolderPage(relay: relay, title: 'Health', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [SwitchListTile(
          title: const Text('Health'),
          subtitle: Text(settings.health ? sentLine(relay.healthSent, 'reading', DateTime.now()) : 'Steps, heart rate, sleep and more.'),
          value: settings.health,
          onChanged: settings.sending ? (on) => apply(context, relay.setHealth(on)) : null,
        )]),
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Health', scanner: scanner),
      ];
    });
  }
}

/// *Calendar*: the switch, when events last went, and while on each of the phone's calendars with its own switch.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key, required this.relay, this.scanner});

  final Relay relay;
  final Scanner? scanner;

  @override
  Widget build(BuildContext context) {
    return _FolderPage(relay: relay, title: 'Calendar', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [SwitchListTile(
          title: const Text('Calendar'),
          subtitle: Text(settings.calendar ? sentLine(relay.calendarSent, 'event', DateTime.now()) : 'Your phone\'s calendars.'),
          value: settings.calendar,
          onChanged: settings.sending ? (on) => apply(context, relay.setCalendar(on)) : null,
        )]),
        if (settings.calendar && relay.calendars.isNotEmpty) Group(title: 'Calendars', children: [
          for (final calendar in relay.calendars) SwitchListTile(
            title: Text(calendar.name),
            subtitle: calendar.account == null || calendar.account!.isEmpty ? null : Text(calendar.account!),
            value: !settings.calendarsOff.contains(calendar.id),
            onChanged: (on) => relay.setCalendarShown(calendar.id, on),
          ),
        ]),
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Calendar', scanner: scanner),
      ];
    });
  }
}

/// *Photos*: the switch that sends each new photo, and whether photos may go on mobile data.
class PhotosPage extends StatelessWidget {
  const PhotosPage({super.key, required this.relay, this.scanner, this.opener});

  final Relay relay;
  final Scanner? scanner;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    return _FolderPage(relay: relay, title: 'Photos', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [
          SwitchListTile(
            title: const Text('Photos'),
            subtitle: Text(settings.place == SendPlace.webhook && settings.sending
              ? 'Sends new photos, with when and where you took them, to your webhook.'
              : 'Sends new photos, with when and where you took them, so your AI can see them.'),
            value: settings.photos,
            onChanged: settings.sending ? ((on) => on ? apply(context, relay.setPhotos(true)) : _stopPhotos(context)) : null,
          ),
          SwitchListTile(
            title: const Text('Send photos on mobile data'),
            subtitle: const Text('Off: photos wait for Wi-Fi.'),
            value: settings.photosOnMobileData,
            onChanged: settings.photos ? (on) => apply(context, relay.setPhotosOnMobileData(on)) : null,
          ),
        ]),
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Photos', scanner: scanner),
      ];
    });
  }

  /// Says where the photos already sent stay, then turns photos off, or opens the page to delete them. Photos sent to
  /// a webhook are in the person's own database, so with the webhook they turn off with no question.
  Future<void> _stopPhotos(BuildContext context) async {
    if (relay.settings.place == SendPlace.webhook) return apply(context, relay.setPhotos(false));
    final server = relay.server;
    final choice = await showDialog<_PhotosChoice>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stop sending photos?'),
      content: const Text('Photos already sent stay on your Relay Everything server. Delete them on your page.'),
      actions: [
        if (server != null)
          TextButton(onPressed: () => Navigator.pop(context, _PhotosChoice.openPage), child: const Text('Open my page')),
        FilledButton(onPressed: () => Navigator.pop(context, _PhotosChoice.stop), child: const Text('Stop sending photos')),
      ],
    ));
    if (!context.mounted) return;
    if (choice == _PhotosChoice.stop) return apply(context, relay.setPhotos(false));
    if (choice == _PhotosChoice.openPage) {
      // Photos stay on: the person deletes what was sent on the page, then can come back and turn them off.
      final messenger = ScaffoldMessenger.of(context);
      if (!await (opener ?? openInBrowser)(Uri.parse('$server/apps/relay/'))) {
        messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
      }
    }
  }
}

/// *Sending*: the *Send my notes* switch, where the phone sends, the webhook and its test, *Open your Relay Everything
/// page*, the server, and *Disconnect this phone*.
class SendingPage extends StatelessWidget {
  const SendingPage({super.key, required this.relay, this.scanner, this.opener});

  final Relay relay;
  final Scanner? scanner;
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    return _FolderPage(relay: relay, title: 'Sending', groups: (context) {
      final settings = relay.settings;
      final sending = settings.sending;
      final danger = Theme.of(context).colorScheme.error;
      return [
        Group(children: [
          SwitchListTile(
            title: const Text('Send my notes'),
            subtitle: Text(_placeLine(relay)),
            value: sending,
            onChanged: (on) => on ? choosePlace(context, relay, scanner) : _stopSending(context),
          ),
          if (sending) ListTile(
            title: const Text('Where the phone sends'),
            subtitle: Text(settings.place == SendPlace.webhook ? 'My own webhook' : 'Relay Everything'),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => choosePlace(context, relay, scanner),
          ),
        ]),
        if (sending && settings.place == SendPlace.webhook) Group(children: [
          ListTile(
            title: const Text('Webhook'),
            subtitle: Text(relay.webhookAddress ?? ''),
            trailing: TextButton(onPressed: () => _test(context), style: quietButton(context), child: const Text('Send a test')),
          ),
          if (relay.webhookProblem case final problem?) ListTile(
            subtitle: Text(problemLine(problem, DateTime.now()), style: TextStyle(color: danger)),
          ),
          ListTile(
            title: const Text('Notes from elsewhere'),
            subtitle: const Text('Sync is off while the phone sends to your own webhook. To get notes from your other '
              'phones and email here, send to Relay Everything, then add your webhook on your Relay Everything page.'),
            trailing: const Icon(CupertinoIcons.arrow_up_right_square),
            onTap: () => _openWebhooks(context),
          ),
        ]),
        if (relay.connected && settings.place == SendPlace.server) Group(children: [
          // Ring notes and recordings are on the Relay Everything page; nothing of this phone's goes there while it
          // sends to the person's own webhook.
          if (sending && relay.server != null) ListTile(
            title: const Text('Open your Relay Everything page'),
            subtitle: const Text('Your ring notes, recordings and the notes from all your devices.'),
            trailing: const Icon(CupertinoIcons.arrow_up_right_square),
            onTap: () => _openPage(context),
          ),
          ListTile(
            title: const Text('Server'),
            subtitle: Text(relay.server ?? ''),
            trailing: const Icon(CupertinoIcons.pencil),
            onTap: () => _editServer(context),
          ),
          ListTile(
            title: Text('Disconnect this phone', style: TextStyle(color: danger)),
            subtitle: const Text('Removes the key from this phone and turns sending off. Notes from this phone stay here. '
              'Notes from elsewhere go.'),
            onTap: () => _disconnect(context),
          ),
        ]),
      ];
    });
  }

  /// The *Webhooks* part of the person's Relay Everything page, where a webhook gets the notes from every device.
  Future<void> _openWebhooks(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await (opener ?? openInBrowser)(Uri.parse('${relay.server ?? defaultServer}/apps/relay/#webhooks'))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }

  Future<void> _test(BuildContext context) async {
    final answer = await relay.testWebhook(relay.webhookAddress ?? '', relay.webhookSecret ?? '');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(answer)));
  }

  Future<void> _stopSending(BuildContext context) async {
    final there = relay.settings.place == SendPlace.webhook ? 'at your webhook' : 'on your Relay Everything server';
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stop sending?'),
      content: Text('New notes stay on this phone. Notes already $there stay there. '
        'Health, the calendar, location and photos stop.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sending')),
      ],
    ));
    if (sure == true) await relay.stopSending();
  }

  /// The person's Relay Everything page, in the phone's browser.
  Future<void> _openPage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await (opener ?? openInBrowser)(Uri.parse('${relay.server}/apps/relay/'))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }

  Future<void> _editServer(BuildContext context) async {
    final address = await showDialog<String>(context: context, builder: (context) => ServerDialog(server: relay.server));
    if (address != null && context.mounted) await apply(context, relay.setServer(address));
  }

  Future<void> _disconnect(BuildContext context) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Disconnect this phone?'),
      content: const Text('Sending turns off. Notes from your other phones and email leave this phone. '
        'You need a new key to send again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
      ],
    ));
    if (sure == true) await relay.disconnect();
  }
}

/// One group of rows: a small muted heading, when it has one, and one card with its rows and no lines between them.
class Group extends StatelessWidget {
  const Group({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title case final title?)
        Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(title,
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: const FontWeight(650), color: theme.colorScheme.onSurfaceVariant)))
      else
        const SizedBox(height: 12),
      Card(clipBehavior: Clip.antiAlias, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children))),
    ]);
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
