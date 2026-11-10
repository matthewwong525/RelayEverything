import 'package:url_launcher/url_launcher.dart';

/// Opens [address] in the browser. Off the web the app has no window of its own to send there.
Future<void> navigateTo(Uri address) async {
  try {
    await launchUrl(address, mode: LaunchMode.externalApplication);
  } on Exception {
    // Nothing opened: the person stays where they were and can try again.
  }
}
