import { useState } from 'react'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from '@/components/ui/alert-dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import { Failed } from './Failed'
import { post, useGet, when } from './read'
import { ClaudeSteps, PebbleSteps, PhoneSteps, type Made } from './Setup'

// Each device's own key: a phone, the Pebble app or Claude Code. A key only adds data, shows once, and turns off
// alone. app/worker/apps/relay/ answers.
type Device = { id: string; name: string; reaches: 'phone' | 'chats'; createdAt: number; revokedAt: number | null }
type Kind = 'phone' | 'pebble' | 'claude'

const KINDS: Record<Kind, { label: string; name: string; reaches: Made['reaches'] }> = {
  phone: { label: 'Phone', name: 'Phone', reaches: 'phone' },
  pebble: { label: 'Pebble app', name: 'Pebble app', reaches: 'phone' },
  claude: { label: 'Claude Code', name: 'Laptop', reaches: 'chats' },
}

function Steps({ kind, made }: { kind: Kind; made: Made }) {
  if (kind === 'pebble') return <PebbleSteps made={made} origin={window.location.origin} />
  return kind === 'claude' ? <ClaudeSteps made={made} /> : <PhoneSteps made={made} />
}

/** *Add a device*: a name and a kind, then its key, shown once. */
function AddDevice({ onAdded }: { onAdded: () => void }) {
  const [open, setOpen] = useState(false)
  const [kind, setKind] = useState<Kind>('phone')
  const [name, setName] = useState('')
  const [made, setMade] = useState<Made | null>(null)
  const [error, setError] = useState('')
  // Closing forgets the key: the page never shows it again.
  const close = (next: boolean) => {
    setOpen(next)
    if (!next) { setMade(null); setName(''); setKind('phone'); setError('') }
  }
  const add = async () => {
    try {
      setMade(await post<Made>('devices', { name: name.trim() || KINDS[kind].name, reaches: KINDS[kind].reaches }))
      onAdded()
    } catch (caught) { setError((caught as Error).message) }
  }
  return <Dialog open={open} onOpenChange={close}>
    <DialogTrigger asChild><Button type="button">Add a device</Button></DialogTrigger>
    <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
      {made === null ? <>
        <DialogHeader>
          <DialogTitle>Add a device</DialogTitle>
          <DialogDescription>Each device gets its own key. A key can only add data, and you can turn it off alone.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2"><Label htmlFor="device-kind">Device</Label>
            <NativeSelect id="device-kind" value={kind} onChange={(event) => setKind(event.target.value as Kind)}>
              {Object.entries(KINDS).map(([value, { label }]) => <NativeSelectOption key={value} value={value}>{label}</NativeSelectOption>)}
            </NativeSelect></div>
          <div className="grid gap-2"><Label htmlFor="device-name">Name</Label>
            <Input id="device-name" maxLength={60} value={name} placeholder={KINDS[kind].name} onChange={(event) => setName(event.target.value)} /></div>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter><Button type="button" variant="outline" onClick={() => close(false)}>Cancel</Button><Button type="button" onClick={add}>Make the key</Button></DialogFooter>
      </> : <>
        <DialogHeader>
          <DialogTitle>Connect {made.name}</DialogTitle>
          <DialogDescription>Relay Everything shows this key once. Finish these steps before you close this window.</DialogDescription>
        </DialogHeader>
        <Steps kind={kind} made={made} />
        <DialogFooter><Button type="button" onClick={() => close(false)}>Done</Button></DialogFooter>
      </>}
    </DialogContent>
  </Dialog>
}

function TurnOff({ device, onOff }: { device: Device; onOff: (error: string) => void }) {
  const off = () => post('devices/off', { id: device.id }).then(() => onOff(''), (caught: Error) => onOff(caught.message))
  return <AlertDialog>
    <AlertDialogTrigger asChild><Button type="button" variant="ghost" size="sm">Turn off</Button></AlertDialogTrigger>
    <AlertDialogContent>
      <AlertDialogHeader>
        <AlertDialogTitle>Turn off {device.name}?</AlertDialogTitle>
        <AlertDialogDescription>Its key stops working at once. What it sent stays. To use the device again, add it again.</AlertDialogDescription>
      </AlertDialogHeader>
      <AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={off}>Turn off</AlertDialogAction></AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>
}

/** The person's devices, newest key first as the server lists them, each with *Turn off* while its key works. */
export function Devices() {
  const [devices, retry] = useGet<{ devices: Device[] }>('devices')
  const [error, setError] = useState('')
  const changed = (message: string) => { setError(message); retry() }
  return <section className="grid gap-3" aria-label="Devices">
    <div className="flex flex-wrap items-center gap-2"><h2 className="grow">Devices</h2><AddDevice onAdded={retry} /></div>
    {devices.status === 'loading' && <p className="text-muted-foreground">Loading devices…</p>}
    {devices.status === 'failed' && <Failed what="Devices" retry={retry} />}
    {devices.status === 'ready' && (devices.value.devices.length === 0
      ? <p className="text-muted-foreground">No devices yet. Add a phone, the Pebble app or Claude Code to start sending.</p>
      : <Card className="grid gap-2 p-4">{devices.value.devices.map((device) => <div key={device.id} className="flex flex-wrap items-center gap-2">
        <span className="grow wrap-anywhere">{device.name}</span>
        <span className="text-sm text-muted-foreground">{device.reaches === 'chats' ? 'Chats' : 'Notes, health and places'} · added {when(device.createdAt)}</span>
        {device.revokedAt === null ? <TurnOff device={device} onOff={changed} /> : <Badge variant="outline">Off</Badge>}
      </div>)}</Card>)}
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
  </section>
}
