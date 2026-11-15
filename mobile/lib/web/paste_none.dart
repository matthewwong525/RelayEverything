/// Takes a paste's [html] and [plain] words, and says whether it put them in.
typedef PasteTaker = bool Function({String? html, required String plain});

/// No browser paste comes outside a browser; the returned function stops nothing.
void Function() listenPastes(PasteTaker take) => () {};
