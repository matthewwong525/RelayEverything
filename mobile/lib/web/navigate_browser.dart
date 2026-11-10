import 'package:web/web.dart' as web;

/// Opens [address] in this window, as a link would: the page goes, and the address's answer shows.
Future<void> navigateTo(Uri address) async => web.window.location.assign(address.toString());
