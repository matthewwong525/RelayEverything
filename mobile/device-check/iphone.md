## This device

- An iPhone simulator on a Mac. The app id is `com.matthewwong525.relayApp`. The app is open on the booted iPhone.
- Take a screenshot: `xcrun simctl io booted screenshot out/claude/<name>.png`. Then Read the file to look at it.
- Tap, type and swipe: write a Maestro flow to `out/claude/flows/<name>.yaml`, then run it with exactly
  `bash mobile/device-check/flow.sh out/claude/flows/<name>.yaml`. Do not run `maestro` yourself: it is refused.
  `flow.sh` stops a flow after 90 seconds and tries once more, so give it up to 4 minutes. Its last line is `result=passed`, `result=failed` or
  `result=hung`. After `result=hung`, take a screenshot, and try a smaller flow or mark the scenario *could not
  check*. A flow starts with `appId: com.matthewwong525.relayApp` and `---`. Tap by the visible text, such as
  `- tapOn: "New note"`. Do not use `launchApp` with `clearState` unless you want a fresh install.
- Examples of flows: `mobile/device-check/flows/`.
- Set where the iPhone is: `xcrun simctl location booted set <latitude>,<longitude>`.
- Open a link in the iPhone: `xcrun simctl openurl booted <url>`.
