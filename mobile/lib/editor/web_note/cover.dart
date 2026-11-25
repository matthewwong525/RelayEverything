import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// The app's own layers over the note's page in the browser. The page is a frame of the browser's page, under the
/// app's drawing: a click over it goes to the frame, not to the app's dialog or menu on top. While a dialog, a sheet
/// or a menu of the app is open, the frame takes no click ([NoteCover.open]); a bar that always lies over the words
/// takes its own clicks ([overNote]). A phone and the Mac need neither: the app takes each touch over its web view.
abstract final class NoteCover {
  /// How many of the app's layers are open over the page now.
  static final open = ValueNotifier<int>(0);

  /// A dialog, a sheet or a menu opened.
  static void opened() => open.value++;

  /// One closed.
  static void closed() {
    if (open.value > 0) open.value--;
  }

  /// Counts each dialog, sheet and pop-up of the app's navigator.
  static final observer = _Observer();
}

class _Observer extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) NoteCover.opened();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) NoteCover.closed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) NoteCover.closed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PopupRoute) NoteCover.closed();
    if (newRoute is PopupRoute) NoteCover.opened();
  }
}

/// [child], a bar that lies over the note's words, taking its own clicks in the browser.
Widget overNote(Widget child) => PointerInterceptor(intercepting: kIsWeb, child: child);

/// A menu's state that counts in [NoteCover] while its menu is open: [menuOpened] and [menuClosed] are its menu's
/// `onOpen` and `onClose`. A menu that goes while open, which calls no `onClose`, stops counting too.
mixin CoversNote<T extends StatefulWidget> on State<T> {
  bool _covering = false;

  void menuOpened() {
    if (_covering) return;
    _covering = true;
    NoteCover.opened();
  }

  void menuClosed() {
    if (!_covering) return;
    _covering = false;
    NoteCover.closed();
  }

  @override
  void dispose() {
    menuClosed();
    super.dispose();
  }
}

/// [child], counted in [NoteCover] for as long as it is shown: a layer that can go with no close call, such as the
/// left bar's drawer, which a resize takes away while open.
class CoversWhileShown extends StatefulWidget {
  const CoversWhileShown({super.key, required this.child});

  final Widget child;

  @override
  State<CoversWhileShown> createState() => _CoversWhileShownState();
}

class _CoversWhileShownState extends State<CoversWhileShown> with CoversNote {
  @override
  void initState() {
    super.initState();
    menuOpened();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
