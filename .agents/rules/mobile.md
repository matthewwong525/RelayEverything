---
paths: ["mobile/**"]
---

# Check a phone app change on an iPhone

A plan that changes a phone screen draws real *Before* and *After* pictures with a screen test, not a `screen` sketch: [real pictures of a phone app screen](../../wiki/development/phone-pictures.md).

When [`/verify`](../skills/verify/SKILL.md) checks a change that touches `mobile/`, it also runs [the device check](../../wiki/development/device-check.md) on the saved commit, once per walk, in the background:

```
node scripts/device-check.mjs run --ref <branch> --sha <saved commit> --pr <n> --scenarios-file <file> --recheck [--flows <name,name>]
```

- **The scenarios file** holds the change's scenarios that the phone app can show, each a `Scenario: <name>` line, then its WHEN and THEN, in plain words. Write it in a temporary folder, never in the repository. Keep each name the same between checks: `--recheck` matches the names.
- **`--recheck` sends Claude only the scenarios that were not *works* in the branch's last finished check**, and prints `recheck=` with that check's link, or `recheck=none` with `recheck_reason=`. Add back by hand any scenario whose screen the fix touched; for a full check, leave `--recheck` out.
- **Tell the person the `tour=` line when it shows**, at about 25 minutes, with `tour_reason=`: the tour passed and Claude is checking, or the tour is broken and why. `tour=broken` ends the check; the full result follows soon.
- **Name the change's own tour step with `--flows`.** A phone change writes a Maestro flow for its main path in [`mobile/device-check/flows/`](../../mobile/device-check/flows/) when the simulator can show it: no microphone sound, no health data, no server. It runs in the tour after the fixed steps, with no AI and with a second try, and Claude looks only at what a flow can't. The flow stays in the folder after the change ships; it joins the fixed tour only by a later choice.
- **Show the results in the chat:** `report.md` from `folder=`, each picture in `tour/` and `claude/`, the place of `run.mp4`, and the `run=` link. On `no-verdict`, also show the last lines of `claude/steps.md`. A report that starts with *The app crashed* names the crash: show those lines first.
- **Map `result=` into the walk's verdicts:** `works` is evidence for SUCCESS, still graded against each scenario; `broken` is FAILURE; `could-not-check`, `no-verdict`, `cancelled` and `failed` are UNKNOWN, with the `reason=` line; `timeout` is TIMEOUT, with what finished. A `cancelled` check that a newer one replaced is not run again: the newer one gives the result.
- **A run spends Claude usage.** Start one per walk, never in a loop. While GitHub can't start the workflow by hand (it has never run), the script starts it by the *check on iPhone* label: the tour runs its fixed steps alone, and Claude reads the open change's specs.
