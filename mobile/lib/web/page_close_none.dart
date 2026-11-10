/// Off the web no page closes: [run] never runs.
void onPageClose(void Function() run) {}

/// Off the web nothing sends as a page closes.
void sendAsPageCloses(String method, Uri address, [String? json]) {}
