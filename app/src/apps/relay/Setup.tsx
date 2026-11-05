import type { ReactNode } from 'react'
import { CopyText } from '@/components/CopyText'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'

const RELEASES = 'https://github.com/matthewwong525/RelayEverything/releases/latest'
const TESTFLIGHT = 'https://apps.apple.com/app/testflight/id899247664'

function SetupDialog({ label, title, description, children }: { label: string; title: string; description: string; children: ReactNode }) {
  return <Dialog>
    <DialogTrigger asChild><Button type="button" variant="ghost">{label}</Button></DialogTrigger>
    <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
      <DialogHeader>
        <DialogTitle>{title}</DialogTitle>
        <DialogDescription>{description}</DialogDescription>
      </DialogHeader>
      <ol className="grid list-decimal gap-3 pl-5">{children}</ol>
    </DialogContent>
  </Dialog>
}

const Code = ({ children }: { children: string }) => <code className="rounded bg-muted px-1 wrap-anywhere">{children}</code>

/** How a phone gets the app and its own key. The app keeps notes on the phone until sending is turned on. */
export function PhoneSetup({ origin }: { origin: string }) {
  return <SetupDialog label="Set up a phone" title="Set up a phone"
    description="The app keeps notes on the phone until you turn on sending. Each phone has its own key, so you can turn one off alone.">
    <li>Install the app: on Android, the newest file from <a className="underline" href={RELEASES}>Relay's releases</a>; on iPhone, the
      newest build in <a className="underline" href={TESTFLIGHT}>TestFlight</a>.</li>
    <li>Ask your assistant to make a key for the phone, or run <Code>node scripts/relay-device-key.mjs create --name "Android phone"</Code>.
      Add <Code>--staging</Code> for a preview.</li>
    <li>The key shows once, as a QR code in the terminal and on a private page.</li>
    <li>In the app, open <b>Settings</b> and turn on <b>Send to your Relay server</b>. Then tap <b>Scan the QR code</b>, or paste
      the key. The server address is:
      <div className="mt-2"><CopyText text={origin} label="Copy the address" /></div></li>
  </SetupDialog>
}

/** What to enter in the Pebble app so the ring's notes come here. */
export function PebbleSetup({ origin }: { origin: string }) {
  const url = `${origin}/apps/relay/api/pebble`
  return <SetupDialog label="Pebble webhook" title="Pebble webhook" description="Send each ring note here from the Pebble app.">
    <li>Make the Pebble app's key: <Code>node scripts/relay-device-key.mjs create --name "Pebble app"</Code>.</li>
    <li>In the Pebble app, open <b>Index 01 Settings</b>, then <b>Webhook</b>, then <b>Hold &amp; talk</b>. Enter this address:
      <div className="mt-2"><CopyText text={url} label="Copy the webhook address" /></div></li>
    <li>Add two headers from the key: <Code>CF-Access-Client-Id</Code> and <Code>CF-Access-Client-Secret</Code>.</li>
    <li>Turn on <b>Sign requests</b> and enter the signing secret your assistant gives you on a private page.</li>
    <li>Choose <b>Both</b>, so each note sends its words and its recording.</li>
    <li>Tap <b>Send test event</b>. When it shows success, tap <b>Save</b>.</li>
  </SetupDialog>
}
