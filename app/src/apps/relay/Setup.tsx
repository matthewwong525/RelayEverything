import { encode } from 'uqr'
import { CopyText } from '@/components/CopyText'

// What a new device's person does with its key, which the page shows once: scan it on a phone, enter it in the
// Pebble app, or paste it in Claude Code. app/worker/apps/relay/ makes the key.
const RELEASES = 'https://github.com/matthewwong525/RelayEverything/releases/latest'
const TESTFLIGHT = 'https://apps.apple.com/app/testflight/id899247664'

/** A new key as the server answers it: `qr` is the text a phone scans and Claude Code takes. */
export type Made = { id: string; name: string; reaches: 'phone' | 'chats'; key: string; qr: string; pebbleSecret: string | null }

const Code = ({ children }: { children: string }) => <code className="rounded bg-muted px-1 wrap-anywhere">{children}</code>

/** The text as a QR code, drawn as one SVG path with the quiet zone a scanner needs. */
function Qr({ text, label }: { text: string; label: string }) {
  const { size, data } = encode(text, { ecc: 'M', border: 4 })
  const path = data.flatMap((row, y) => row.map((dark, x) => dark ? `M${x} ${y}h1v1h-1z` : '')).join('')
  return <svg role="img" aria-label={label} viewBox={`0 0 ${size} ${size}`} className="mx-auto w-full max-w-64 bg-white" shapeRendering="crispEdges">
    <path d={path} fill="black" />
  </svg>
}

export function PhoneSteps({ made }: { made: Made }) {
  return <ol className="grid list-decimal gap-3 pl-5">
    <li>Install the app: on Android, the newest file from <a className="underline" href={RELEASES}>Relay Everything's releases</a>; on iPhone, the
      newest build in <a className="underline" href={TESTFLIGHT}>TestFlight</a>.</li>
    <li>In the app, open <b>Settings</b> and turn on <b>Send to Relay Everything</b>. Then tap <b>Scan the QR code</b> and scan this code:
      <div className="mt-2"><Qr text={made.qr} label={`QR code for ${made.name}`} /></div></li>
    <li>No camera? Paste the code in the app:<div className="mt-2"><CopyText text={made.qr} label="Copy the code" /></div></li>
  </ol>
}

export function PebbleSteps({ made, origin }: { made: Made; origin: string }) {
  return <ol className="grid list-decimal gap-3 pl-5">
    <li>In the Pebble app, open <b>Index 01 Settings</b>, then <b>Webhook</b>, then <b>Hold &amp; talk</b>. Enter this address:
      <div className="mt-2"><CopyText text={`${origin}/apps/relay/api/pebble`} label="Copy the webhook address" /></div></li>
    <li>Add a header named <Code>Authorization</Code> with this value:
      <div className="mt-2"><CopyText text={`Bearer ${made.key}`} label="Copy the header value" /></div></li>
    {made.pebbleSecret && <li>Turn on <b>Sign requests</b> and enter this signing secret:
      <div className="mt-2"><CopyText text={made.pebbleSecret} label="Copy the signing secret" /></div></li>}
    <li>Choose <b>Both</b>, so each note sends its words and its recording.</li>
    <li>Tap <b>Send test event</b>. When it shows success, tap <b>Save</b>.</li>
  </ol>
}

export function ClaudeSteps({ made }: { made: Made }) {
  return <ol className="grid list-decimal gap-3 pl-5">
    <li>Copy the connect code:<div className="mt-2"><CopyText text={made.qr} label="Copy the connect code" /></div></li>
    <li>In Claude Code, add the plugin: <Code>/plugin marketplace add matthewwong525/RelayEverything</Code>, then{' '}
      <Code>/plugin install relay@relay</Code>.</li>
    <li>Paste the connect code when Claude Code asks. The key can only add chats.</li>
  </ol>
}
