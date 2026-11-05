// Where a webhook may send: an outside https address. The server would else call addresses an attacker picks, such as
// a private network or Relay's own site. Each refusal is an error code the routes document.

const PRIVATE_NAMES = /(?:^|\.)(?:localhost|local|internal)$/;
const IPV4 = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
// Network and prefix length, as 32-bit numbers: 0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.168/16.
const PRIVATE_V4: [number, number][] = [[0x00000000, 8], [0x0a000000, 8], [0x64400000, 10], [0x7f000000, 8], [0xa9fe0000, 16],
  [0xac100000, 12], [0xc0a80000, 16]];

export type Refusal = "address_invalid" | "address_not_https" | "address_has_login" | "address_private" | "address_own_site";

export const REFUSALS: Record<Refusal, string> = {
  address_invalid: "That is not a web address.",
  address_not_https: "The address must start with https://.",
  address_has_login: "The address can't hold a user name or password.",
  address_private: "The address can't be this computer or a private network.",
  address_own_site: "The address can't be Relay's own site.",
};

const privateV4 = (address: number) => PRIVATE_V4.some(([network, bits]) => (address >>> (32 - bits)) === (network >>> (32 - bits)));

/** An IPv6 address's eight 16-bit groups. The URL parser has already checked and shortened it. */
function groupsOf(host: string): number[] {
  const [head, tail] = host.split("::");
  const part = (text: string | undefined) => text ? text.split(":").map(group => parseInt(group, 16)) : [];
  const [start, end] = [part(head), part(tail)];
  return tail === undefined ? start : [...start, ...Array(8 - start.length - end.length).fill(0), ...end];
}

function privateV6(host: string): boolean {
  const groups = groupsOf(host);
  const zeros = (count: number) => groups.slice(0, count).every(group => group === 0);
  // ::ffff:a.b.c.d reaches an IPv4 address; ::1 and :: are this computer.
  if (zeros(5) && groups[5] === 0xffff) return privateV4(((groups[6] << 16) | groups[7]) >>> 0);
  if (zeros(7) && groups[7] <= 1) return true;
  return (groups[0] & 0xfe00) === 0xfc00 || (groups[0] & 0xffc0) === 0xfe80;
}

function privateHost(host: string): boolean {
  if (PRIVATE_NAMES.test(host)) return true;
  if (host.startsWith("[")) return privateV6(host.slice(1, -1));
  const v4 = IPV4.exec(host);
  return v4 !== null && privateV4(v4.slice(1).reduce((sum, byte) => sum * 256 + Number(byte), 0));
}

/** The site itself, its subdomains, and on workers.dev the account's other Workers, such as its previews. */
function ownSite(host: string, site: string): boolean {
  const within = (root: string) => host === root || host.endsWith(`.${root}`);
  return within(site) || (site.endsWith(".workers.dev") && within(site.split(".").slice(-3).join(".")));
}

/** Why Relay won't send to `url`, or null when it may. The sender checks again before each send, without `siteHost`. */
export function checkAddress(url: string, siteHost?: string): Refusal | null {
  if (!URL.canParse(url)) return "address_invalid";
  const parsed = new URL(url);
  if (parsed.protocol !== "https:") return "address_not_https";
  if (parsed.username || parsed.password) return "address_has_login";
  const host = parsed.hostname.replace(/\.$/, "");
  if (privateHost(host)) return "address_private";
  return siteHost && ownSite(host, siteHost.toLowerCase()) ? "address_own_site" : null;
}
