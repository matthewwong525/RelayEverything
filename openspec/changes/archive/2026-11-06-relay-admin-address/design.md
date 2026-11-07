## Context

The open Relay Everything server (`relay-everything-server`, `app/wrangler.relay.jsonc`) claims app.relayeverything.com as a custom domain. The company app (`relay-everything`, `app/wrangler.jsonc`) held the same domain. A Worker custom domain has one Worker, and a deploy claims the domains its config names.

## Decisions

- The company app's production route becomes `admin.relayeverything.com`. Its Access app has a Worker destination, so the login covers each of the Worker's domains with no Access change. Checked live: admin.relayeverything.com answers 302 to the Access login.
- `.agents/.wong-stack.json` points `memory.worker` and `companyApi.origin` at admin.relayeverything.com, because only the company app serves `/_memory` and the company API.
- `scripts/relay-forward` keeps `TARGET` at app.relayeverything.com: the person's data is there now.
- The site guard reads the hosts in `app/wrangler.jsonc`, so it now refuses admin.relayeverything.com, the private address, and no longer refuses app.relayeverything.com, the open one.

## Risks

- A main deploy from before this change would take app.relayeverything.com back. Ship this change before any other publish.
