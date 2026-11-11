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

/// [part] of the person's Relay Everything page, such as `#webhooks`, in the phone's browser, and a message if the
/// browser did not open. A test passes its own [opener].
Future<void> openRelayPage(BuildContext context, Relay relay, String part, {Opener? opener}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await (opener ?? openInBrowser)(Uri.parse('${relay.server ?? defaultServer}/$part'))) {
    messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
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

/// What a folder's switch says about sending: *Sent 14:05 · 3 waiting*, with the date when it was not today. With
/// [webhook], as when private data goes to the person's own webhook: *Sent to your webhook 14:05 · 3 waiting*.
String sentLine(SendState state, String what, DateTime now, {bool webhook = false}) {
  final at = state.at;
  final waiting = switch (state.waiting) { 0 => 'none waiting', 1 => '1 $what waiting', final n => '$n ${what}s waiting' };
  if (at == null) return 'Not sent yet · $waiting';
  return 'Sent ${webhook ? 'to your webhook ' : ''}${_when(at, now)} · $waiting';
}

/// True when health, places, the calendar and photos go to the person's own webhook.
bool _toWebhook(Relay relay) => relay.settings.privatePlace == SendPlace.webhook;

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

/// The host of an address, such as *app.relayeverything.com*, or empty.
String hostOf(String? address) => Uri.tryParse(address ?? '')?.host ?? '';

/// What the Account page says about the webhook's last problem: a refused file, an answer that was not 2xx, or none.
/// [what] names what waits: notes, or the private data that goes only to the webhook.
String problemLine(WebhookProblem problem, DateTime now, {String what = 'Notes'}) {
  final at = _when(problem.at, now);
  if (problem.file != null) return '${problem.file} was too large for your receiver ($at), so it was not sent.';
  if (problem.status == null) return 'No answer from your receiver at $at. $what wait on this phone until it answers.';
  return 'Your receiver answered ${problem.status} at $at. $what wait on this phone until it takes them.';
}

/// Runs a change and shows why it could not be, if it could not.
Future<void> apply(BuildContext context, Future<String?> change) async {
  final problem = await change;
  if (problem != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
}

/// *Sign in*: sets up where to send, a key or the person's own webhook. Then asks about the notes that never went, and
/// turns sending on there, in the same step. The Account row in Settings and a folder's *Sign in* both start here. With
/// [keepWebhook], the webhook Account page's *Sign in to Relay Everything* starts here too: it offers only the sign-in,
/// and health, places, the calendar and photos stay on the person's own webhook, as *Only to my own webhook*. True once
/// sending starts; a closed sign-in or question changes nothing.
Future<bool> choosePlace(BuildContext context, Relay relay, {bool keepWebhook = false}) async {
  final place = await Navigator.of(context).push(MaterialPageRoute<SendPlace>(
    builder: (_) => ConnectScreen(relay: relay, signInOnly: keepWebhook)));
  if (place == null || !context.mounted) return false;
  final fromWebhook = relay.settings.place == SendPlace.webhook && place == SendPlace.server;
  final earlier = await relay.earlierNotes(to: place);
  var sendEarlier = false;
  if (earlier > 0) {
    if (!context.mounted) return false;
    final choice = await showDialog<bool>(context: context,
      builder: (context) => _EarlierDialog(count: earlier, place: place, fromWebhook: fromWebhook));
    if (choice == null) return false;
    sendEarlier = choice;
  }
  if (!context.mounted) return false;
  final problem = await relay.startSending(sendEarlier: sendEarlier, place: place,
    privateTo: keepWebhook ? SendPlace.webhook : null);
  if (problem != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
  return problem == null;
}

/// A page opened from Home: *‹ Home*, or the [back] page's name, a large title, and its groups. Each switch acts at
/// once and asks for its permission only when turned on.
class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.relay, required this.title, required this.groups, this.back = 'Home'});

  final Relay relay;
  final String title;
  final String back;
  final List<Widget> Function(BuildContext context) groups;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) => CustomScrollView(slivers: [
          SliverAppBar.large(leading: BackTo(back), leadingWidth: BackTo.widthOf(back), title: Text(title)),
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: SliverList.list(children: groups(context))),
        ]),
      ),
    );
  }
}

/// With sending off: that the folder works once the person signs in, and *Sign in*, the same sign-in as the Account
/// row in Settings.
class _NeedsSending extends StatelessWidget {
  const _NeedsSending({required this.relay, required this.what});

  final Relay relay;
  final String what;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('$what works once you sign in. Nothing leaves this phone until you do.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        FilledButton(onPressed: () => choosePlace(context, relay), child: const Text('Sign in')),
      ]),
    );
  }
}

/// *Location*: the location history switch, its send state, on iPhone how often it keeps a point, and what it sends.
class LocationPage extends StatelessWidget {
  const LocationPage({super.key, required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'Location', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [SwitchListTile(
          title: const Text('Location history'),
          subtitle: Text(settings.history ? sentLine(relay.pointsSent, 'point', DateTime.now(), webhook: _toWebhook(relay))
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
        if (settings.history) Group(title: 'What to send', children: [RadioGroup<LocationSend>(
          groupValue: settings.locationSend,
          onChanged: (send) { if (send != null) apply(context, relay.setLocationSend(send)); },
          child: const Column(children: [
            RadioListTile(value: LocationSend.all, title: Text('Stays, trips and points'),
              subtitle: Text('Where you stayed, how you moved, and each point on the way.')),
            RadioListTile(value: LocationSend.stays, title: Text('Only stays and trips'),
              subtitle: Text('Where you stayed and how you moved. No point on the way leaves the phone.')),
            RadioListTile(value: LocationSend.points, title: Text('Only points'),
              subtitle: Text('Each point, with its street, as before.')),
          ]),
        )]),
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Location history'),
      ];
    });
  }
}

/// *Health*: the switch for steps, heart rate, sleep and more, and when they last went.
class HealthPage extends StatelessWidget {
  const HealthPage({super.key, required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'Health', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [SwitchListTile(
          title: const Text('Health'),
          subtitle: Text(settings.health ? sentLine(relay.healthSent, 'reading', DateTime.now(), webhook: _toWebhook(relay)) : 'Steps, heart rate, sleep and more.'),
          value: settings.health,
          onChanged: settings.sending ? (on) => apply(context, relay.setHealth(on)) : null,
        )]),
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Health'),
      ];
    });
  }
}

/// *Calendar*: the switch, when events last went, and while on each of the phone's calendars with its own switch.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key, required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'Calendar', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [SwitchListTile(
          title: const Text('Calendar'),
          subtitle: Text(settings.calendar ? sentLine(relay.calendarSent, 'event', DateTime.now(), webhook: _toWebhook(relay)) : 'Your phone\'s calendars.'),
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
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Calendar'),
      ];
    });
  }
}

/// *Photos*: the switch that sends each new photo, and whether photos may go on mobile data.
class PhotosPage extends StatelessWidget {
  const PhotosPage({super.key, required this.relay, this.opener});

  final Relay relay;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'Photos', groups: (context) {
      final settings = relay.settings;
      return [
        Group(children: [
          SwitchListTile(
            title: const Text('Photos'),
            subtitle: Text(_toWebhook(relay) && settings.sending
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
        if (!settings.sending) _NeedsSending(relay: relay, what: 'Photos'),
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
      if (!await (opener ?? openInBrowser)(Uri.parse('$server/'))) {
        messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
      }
    }
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
/// again. With [fromWebhook], the notes went only to the person's own webhook.
class _EarlierDialog extends StatelessWidget {
  const _EarlierDialog({required this.count, required this.place, this.fromWebhook = false});

  final int count;
  final SendPlace place;
  final bool fromWebhook;

  @override
  Widget build(BuildContext context) {
    final where = fromWebhook
      ? '${count == 1 ? 'It is' : 'They are'} not on Relay Everything yet.'
      : '${count == 1 ? 'It was' : 'They were'} only on this phone.';
    return AlertDialog(
      title: Text(count == 1 ? 'Send your earlier note too?' : 'Send your $count earlier notes too?'),
      content: Text('$where New notes go to '
        '${place == SendPlace.webhook ? 'your webhook' : 'your Relay Everything server'} from now on.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Only new notes')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(count == 1 ? 'Send it' : 'Send them')),
      ],
    );
  }
}

/// One folder: its icon in accent, its name, its status line, its count, and a chevron. [ask] shows the line in accent
/// text, as a link. Home's folders and the Account page's *AI apps* and *Webhooks* use it.
class FolderRow extends StatelessWidget {
  const FolderRow({super.key, required this.icon, required this.title, required this.onTap, this.line, this.count,
    this.ask = false, this.trailing = CupertinoIcons.chevron_forward});

  final IconData icon;
  final String title;
  final String? line;
  final int? count;
  final bool ask;
  final VoidCallback onTap;
  /// The chevron, or an arrow out for a row that opens the browser.
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return ListTile(
      leading: Icon(icon, color: brand.accentText),
      title: Text(title, style: TextStyle(fontSize: 16, color: brand.ink)),
      subtitle: line == null ? null : Text(line!, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: ask ? brand.accentText : brand.muted, fontWeight: ask ? FontWeight.w500 : null)),
      trailing: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        if (count != null) Text('$count', style: TextStyle(fontSize: 16, color: brand.muted)),
        Icon(trailing, color: brand.muted),
      ]),
      onTap: onTap,
    );
  }
}
