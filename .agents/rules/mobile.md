---
paths: ["mobile/**"]
---

# Check a phone app change on an iPhone

When [`/verify`](../skills/verify/SKILL.md) checks a change that touches `mobile/`, it also runs [the device check](../../wiki/development/device-check.md) on the saved commit, once per walk:

```
node scripts/device-check.mjs run --ref <branch> --sha <saved commit> --pr <n> --scenarios-file <file>
```

- **The scenarios file** holds the change's scenarios that the phone app can show, each with its WHEN and THEN, in plain words. Write it in a temporary folder, never in the repository.
- **Show the results in the chat:** `report.md` from `folder=`, each picture in `tour/` and `claude/`, the place of `run.mp4`, and the `run=` link.
- **Map `result=` into the walk's verdicts:** `works` is evidence for SUCCESS, still graded against each scenario; `broken` is FAILURE; `could-not-check` and `failed` are UNKNOWN, with the reason; `timeout` is TIMEOUT, with what finished.
- **A run spends the Anthropic key.** Start one per walk, never in a loop. While GitHub can't start the workflow by hand (it has never run), the script starts it by the *check on iPhone* label, and Claude reads the open change's specs.
