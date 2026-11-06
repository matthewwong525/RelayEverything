## This device

- An iPhone simulator on a Mac. The app id is `com.matthewwong525.relayApp`. The app is open on the booted iPhone.
- Take a screenshot: `xcrun simctl io booted screenshot out/claude/<name>.png`. Then Read the file to look at it.
- Tap, type and swipe: write a Maestro flow to `out/claude/flows/<name>.yaml`, then run
  `maestro test out/claude/flows/<name>.yaml`. A flow starts with `appId: com.matthewwong525.relayApp` and `---`. Tap
  by the visible text, such as `- tapOn: "New note"`. Do not use `launchApp` with `clearState` unless you want a fresh
  install.
- Examples of flows: `mobile/device-check/flows/`.
- Set where the iPhone is: `xcrun simctl location booted set <latitude>,<longitude>`.
- Open a link in the iPhone: `xcrun simctl openurl booted <url>`.
