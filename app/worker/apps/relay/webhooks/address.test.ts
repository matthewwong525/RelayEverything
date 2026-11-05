import { expect, it } from "vitest";
import { checkAddress } from "./address.ts";

const SITE = "relay-ring-staging.owner.workers.dev";

it("allows an outside https address", () => {
  for (const url of ["https://db.example.com/relay", "https://203.0.113.9:8443/hook", "https://[2001:db8::1]/hook", "https://[2001:db8:1:2:3:4:5:6]/", "https://172.32.0.1/",
    "https://relay-ring-staging.other.workers.dev/", "https://example.local.com/"]) {
    expect(checkAddress(url, SITE), url).toBeNull();
  }
});

it("refuses an address that is no https web address, or holds a login", () => {
  expect(checkAddress("not an address")).toBe("address_invalid");
  expect(checkAddress("http://db.example.com/hook")).toBe("address_not_https");
  expect(checkAddress("ftp://db.example.com/hook")).toBe("address_not_https");
  expect(checkAddress("https://user:password@db.example.com/hook")).toBe("address_has_login");
  expect(checkAddress("https://user@db.example.com/hook")).toBe("address_has_login");
});

it("refuses this computer and each private range, however the address is written", () => {
  for (const url of ["https://localhost/", "https://api.localhost/", "https://printer.local/", "https://db.internal./", "https://LOCALHOST/",
    "https://0.0.0.0/", "https://10.1.2.3/", "https://100.64.0.1/", "https://100.127.255.255/", "https://127.0.0.1/", "https://127.1/",
    "https://0x7f000001/", "https://169.254.169.254/", "https://172.16.0.1/", "https://172.31.255.255/", "https://192.168.1.10/hook",
    "https://[::1]/", "https://[::]/", "https://[fc00::1]/", "https://[fd12:3456::1]/", "https://[fe80::1]/", "https://[::ffff:127.0.0.1]/",
    "https://[::ffff:192.168.0.1]/"]) {
    expect(checkAddress(url, SITE), url).toBe("address_private");
  }
  expect(checkAddress("https://[::ffff:8.8.8.8]/")).toBeNull();
  expect(checkAddress("https://100.128.0.1/")).toBeNull();
});

it("refuses the site's own host, its subdomains and the account's other Workers", () => {
  for (const url of [`https://${SITE}/apps/relay/api/notes`, `https://x.${SITE}/`, "https://relay-ring.owner.workers.dev/",
    "https://branch-relay-ring-staging.owner.workers.dev/"]) {
    expect(checkAddress(url, SITE), url).toBe("address_own_site");
  }
  expect(checkAddress("https://relay.example.org/hook", "Relay.Example.org")).toBe("address_own_site");
  expect(checkAddress("https://db.example.org/hook", "relay.example.org")).toBeNull();
  expect(checkAddress(`https://${SITE}/`)).toBeNull();
});
