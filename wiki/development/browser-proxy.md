# Browser routes

The browser routes send the shared browser's traffic through saved proxies, so sites see your home address, not this server's data-centre address. [Browsing](browsing.md) owns the browser itself; this page owns its routes.

WongStack does not ship these routes: this repo copied them from WongOS. A [WongStack update](../../.agents/skills/wong-sync/SKILL.md) must keep them.

## The order of routes

Each connection to a site tries these in order, and moves to the next when one fails:

1. **The first proxy**, `BROWSE_FIRST_PROXY`: a proxy at your home, such as a Raspberry Pi that this computer reaches through a private network.
2. **The upstream**, `BROWSE_UPSTREAM_PROXY`: a paid proxy address in your country. It is the backup.
3. **This computer's own network**, so the page still loads.

When the first proxy fails and the upstream then opens the same connection, the first proxy waits 60 seconds: in that time, each new connection starts at the upstream, so pages do not wait on a home proxy that is off. After that, the next connection tries the first proxy again. A connection that is already open keeps its route until the browser closes it. When the upstream also fails on a secure connection, the site is down, not the first proxy: the next connection tries the first proxy again. A plain (not secure) request is different: a first proxy that fails it waits 60 seconds, even when the upstream fails too. Local addresses always go direct. Only the browser uses these routes: other programs on this computer use its own network.

A secure page moves to the next route when a route refuses or fails to open its tunnel, because nothing from the page has left yet. A plain (not secure) request moves on only when a route refused the login or was unreachable. After a route takes a plain request, a failure gives an error page, never a second send.

## Save the routes

Save each key in the primary worktree's `.env` ([how](secrets.md#receive-a-key-through-a-private-link)). [`.env.example`](../../.env.example) holds only the blank names: this repo is public, so a proxy address, login or home address never goes in a file here.

- `BROWSE_FIRST_PROXY` holds `[http://][login:password@]host:port`. The login is optional.
- `BROWSE_UPSTREAM_PROXY` holds `[http://]login:password@host:port`. Pick a sticky address in your country, so sites see one address for a session.

The next browser start copies each line to `~/.wong-stack/camoufox/first-proxy` and `~/.wong-stack/camoufox/upstream-proxy`, readable only by you. A start from any repo uses those files when its own `.env` has no key, so a changed key spreads. While a file is missing, a start reads the old camofox file of the same name in `~/.wong-stack/camofox/` and copies it over. Only the forwarder holds the lines: the browser gets a local forwarder address, never a proxy login.

At start, the browser's time zone follows the address that sites see, and its language is English for that address's country: a Canadian address gives `en-CA`. With no address, it starts in `en-US`.

## Check the live route

`node .claude/skills/browser/scripts/browse.mjs status` prints `BROWSE_NETWORK=`. It only reads: it never starts or stops the browser.

| Value | Meaning |
|---|---|
| `upstream` | through the first proxy, or through the upstream when no first proxy is saved |
| `upstream (backup)` | through the upstream, because the first proxy failed: the home proxy is off or offline |
| `direct (upstream unreachable)` | every route failed: this computer's own network |
| `direct (no upstream proxy)` | no line is saved, or older scripts started the running browser |
| `unknown (browser stopped)` | no browser runs |

A running browser also prints `BROWSE_LANGUAGE=`: `english`, `random (browser tool changed)` (tell the person), or `unknown (started before this fix)` (ask before you restart).

On `direct (upstream unreachable)`, tell the person to check the home proxy and the upstream account.

## Test a change to the routes

CI does not run the browser's tests: it runs `npm test` only at the root and one folder down. After a change to the route scripts, run them yourself:

```bash
node --test .agents/skills/browser/scripts/*.test.mjs
```

Name each file: the folder form, `node --test .agents/skills/browser/scripts/`, fails on Node 22. The tests use local listeners and a temporary home folder, so they never touch the running browser.

## Turn it off

- **Only the first proxy:** blank `BROWSE_FIRST_PROXY` in each repo's `.env` and empty `~/.wong-stack/camoufox/first-proxy`. Empty the file, do not delete it, or the old camofox line comes back. Then restart the browser after the person's yes.
- **Every route:** blank both keys in each repo's `.env` and run `browse.mjs network off`. It empties both computer files. Then restart the browser after the person's yes.

A running browser keeps its route until its next start. Never restart it without a yes: a restart can sign the person out of a step in progress.

Up: [Browsing](browsing.md). Part of [development](README.md).
