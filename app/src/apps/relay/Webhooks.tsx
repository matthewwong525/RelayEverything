import { useCallback, useEffect, useState } from 'react'
import { CopyText } from '@/components/CopyText'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from '@/components/ui/alert-dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { get, post, when, type Webhook, type WebhookKind } from './read'

// Where Relay sends your data: each webhook with its state and actions. app/worker/apps/relay/webhooks/routes.ts
type Changed = (hook: Webhook) => void

const STATE: Record<Webhook['state'], string> = { working: 'Working', paused: 'Paused', failing: 'Failing', backfilling: 'Sending past data' }
const DAY = 86_400_000

const duration = (ms: number) => ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`
const failure = (error: unknown) => (error as Error).message

/** The card's line: what waits, when the next try is, and the last answer. */
function lineOf(hook: Webhook) {
  const answer = hook.lastError ?? (hook.lastStatus === null ? null : `answered ${hook.lastStatus}`)
  return [hook.waiting ? `${hook.waiting} waiting` : null, hook.nextTryAt ? `next try ${when(hook.nextTryAt)}` : null,
    hook.failingSince ? `failing since ${when(hook.failingSince)}` : null, hook.lastSentAt ? `last sent ${when(hook.lastSentAt)}` : null,
    answer && `last answer: ${answer}`].filter(Boolean).join(' · ') || 'nothing sent yet'
}

/** What a test got back, as one sentence. */
function testLine({ status, ms, error }: { status: number | null; ms: number; error: string | null }) {
  return status === null ? `No answer: ${error}` : `Answered ${status} in ${duration(ms)}.${error ? ` ${error}` : ''}`
}

function Secret({ secret }: { secret: string }) {
  return <>
    <Input aria-label="The secret" className="font-mono" value={secret} readOnly />
    <CopyText text={secret} label="Copy the secret" variant="default" shown />
    <p className="text-sm text-muted-foreground">Your database uses it to check each message came from Relay Everything. Lost it? Make a new one from the webhook's card.</p>
  </>
}

function Tick({ checked, onChange, children }: { checked: boolean; onChange: (value: boolean) => void; children: string }) {
  return <Label className="font-normal"><Checkbox checked={checked} onCheckedChange={(value) => onChange(value === true)} />{children}</Label>
}

/** "A, B and C". */
const listed = (words: string[]) => words.length < 2 ? words.join('') : `${words.slice(0, -1).join(', ')} and ${words.at(-1)}`

function AddWebhook({ kinds, onAdd }: { kinds: WebhookKind[]; onAdd: Changed }) {
  const [open, setOpen] = useState(false)
  const [secret, setSecret] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [url, setUrl] = useState('https://')
  const [ticked, setTicked] = useState<string[]>([])
  const [error, setError] = useState('')
  const close = (next: boolean) => {
    setOpen(next)
    if (!next) { setSecret(null); setName(''); setUrl('https://'); setTicked([]); setError('') }
  }
  const tick = (id: string, on: boolean) => setTicked((now) => on ? [...now, id] : now.filter((other) => other !== id))
  const always = kinds.filter((kind) => kind.always)
  const sensitive = kinds.filter((kind) => kind.sensitive).map((kind, index) => index ? kind.label.toLowerCase() : kind.label)
  const add = async () => {
    try {
      const chosen = kinds.filter((kind) => ticked.includes(kind.id)).map((kind) => kind.id)
      const made = await post<{ webhook: Webhook; secret: string }>('webhooks', { name: name.trim() || 'My database', url, kinds: chosen })
      onAdd(made.webhook)
      setSecret(made.secret)
    } catch (caught) { setError(failure(caught)) }
  }
  return <Dialog open={open} onOpenChange={close}>
    <DialogTrigger asChild><Button type="button" variant="ghost">Add a webhook</Button></DialogTrigger>
    <DialogContent>
      {secret === null ? <>
        <DialogHeader>
          <DialogTitle>Add a webhook</DialogTitle>
          <DialogDescription>Relay Everything sends each new note to this address, signed, a few seconds after it gets it.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2"><Label htmlFor="hook-name">Name</Label><Input id="hook-name" value={name} placeholder="My Postgres" onChange={(event) => setName(event.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="hook-url">Address</Label><Input id="hook-url" value={url} onChange={(event) => setUrl(event.target.value)} /></div>
          <div className="grid gap-3">
            {always.map((kind) => <span key={kind.id} className="text-sm">{kind.label} always go, {kind.detail}.</span>)}
            {kinds.filter((kind) => !kind.always).map((kind) => <Tick key={kind.id} checked={ticked.includes(kind.id)} onChange={(on) => tick(kind.id, on)}>
              {kind.detail ? `${kind.label}: ${kind.detail}` : kind.label}</Tick>)}
            {sensitive.length > 0 && <span className="text-sm text-muted-foreground">{listed(sensitive)} are sensitive. Tick them only for a database you control.</span>}
          </div>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter><Button type="button" variant="outline" onClick={() => close(false)}>Cancel</Button><Button type="button" onClick={add}>Add</Button></DialogFooter>
      </> : <>
        <DialogHeader>
          <DialogTitle>Webhook added</DialogTitle>
          <DialogDescription>Copy this secret now. Relay Everything shows it once.</DialogDescription>
        </DialogHeader>
        <Secret secret={secret} />
        <DialogFooter><Button type="button" onClick={() => close(false)}>Done</Button></DialogFooter>
      </>}
    </DialogContent>
  </Dialog>
}

/** A local day a week ago, as a date field holds it. */
const weekAgo = () => new Date(Date.now() - 7 * DAY - new Date().getTimezoneOffset() * 60_000).toISOString().slice(0, 10)

function PastData({ hook, act }: { hook: Webhook; act: (work: () => Promise<{ webhook?: Webhook }>) => Promise<boolean> }) {
  const [open, setOpen] = useState(false)
  const [since, setSince] = useState(weekAgo)
  const send = async () => {
    if (await act(() => post<{ webhook: Webhook }>('webhooks/resend', { id: hook.id, since: new Date(`${since}T00:00`).getTime() }))) setOpen(false)
  }
  return <Dialog open={open} onOpenChange={setOpen}>
    <DialogTrigger asChild><Button type="button" variant="ghost" size="sm">Send past data</Button></DialogTrigger>
    <DialogContent>
      <DialogHeader>
        <DialogTitle>Send past data</DialogTitle>
        <DialogDescription>Relay Everything sends everything this webhook takes, recorded since this day, then carries on with new data.</DialogDescription>
      </DialogHeader>
      <div className="grid gap-2"><Label htmlFor={`since-${hook.id}`}>From</Label><Input id={`since-${hook.id}`} type="date" value={since} onChange={(event) => setSince(event.target.value)} /></div>
      <DialogFooter><Button type="button" disabled={!since} onClick={send}>Send</Button></DialogFooter>
    </DialogContent>
  </Dialog>
}

function Confirm({ label, title, description, onConfirm }: { label: string; title: string; description: string; onConfirm: () => void }) {
  return <AlertDialog>
    <AlertDialogTrigger asChild><Button type="button" variant="ghost" size="sm">{label}</Button></AlertDialogTrigger>
    <AlertDialogContent>
      <AlertDialogHeader>
        <AlertDialogTitle>{title}</AlertDialogTitle>
        <AlertDialogDescription>{description}</AlertDialogDescription>
      </AlertDialogHeader>
      <AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={onConfirm}>{label}</AlertDialogAction></AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>
}

function HookCard({ hook, names, onChange, onRemove }: { hook: Webhook; names: Map<string, string>; onChange: Changed; onRemove: () => void }) {
  const [message, setMessage] = useState('')
  const [secret, setSecret] = useState<string | null>(null)
  // Runs one action; its error shows on the card. True when it worked.
  const act = async (work: () => Promise<{ webhook?: Webhook }>) => {
    try {
      const done = await work()
      if (done.webhook) onChange(done.webhook)
      return true
    } catch (caught) { setMessage(failure(caught)); return false }
  }
  const test = () => act(async () => {
    setMessage('Sending a test…')
    setMessage(testLine(await post<{ status: number | null; ms: number; error: string | null }>('webhooks/test', { id: hook.id })))
    return {}
  })
  const renew = () => act(async () => {
    setSecret((await post<{ secret: string }>('webhooks/secret', { id: hook.id })).secret)
    return {}
  })
  const paused = hook.state === 'paused'
  return <Card className="grid gap-2 p-4" aria-label={hook.name}>
    <div className="flex flex-wrap items-center gap-2">
      <span className="grow font-medium">{hook.name}</span>
      <Badge variant={hook.state === 'failing' ? 'destructive' : paused ? 'outline' : 'default'}>{STATE[hook.state]}</Badge>
    </div>
    <span className="text-sm text-muted-foreground wrap-anywhere">{new URL(hook.url).host} · {hook.kinds.map((kind) => names.get(kind) ?? kind).join(', ')} · {lineOf(hook)}</span>
    <div className="flex flex-wrap gap-1">
      <Button type="button" variant="ghost" size="sm" onClick={test}>Send a test</Button>
      {hook.state === 'failing' ? <Button type="button" variant="ghost" size="sm" onClick={() => act(() => post<{ webhook: Webhook }>('webhooks/retry', { id: hook.id }))}>Try again now</Button>
        : <PastData hook={hook} act={act} />}
      <Confirm label="New secret" title={`Make a new secret for ${hook.name}?`} onConfirm={renew}
        description="The old secret stops working at once. Put the new one in your database before the next message." />
      <Button type="button" variant="ghost" size="sm" onClick={() => act(() => post<{ webhook: Webhook }>('webhooks/update', { id: hook.id, active: paused }))}>{paused ? 'Resume' : 'Pause'}</Button>
      <Confirm label="Remove" title={`Remove ${hook.name}?`} onConfirm={() => act(async () => { await post('webhooks/remove', { id: hook.id }); onRemove(); return {} })}
        description="Relay Everything stops sending to it and deletes its secret and send history. This can't be undone. Your notes stay in Relay Everything." />
    </div>
    {message && <p role="status" className="text-sm">{message}</p>}
    <Dialog open={secret !== null} onOpenChange={() => setSecret(null)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New secret</DialogTitle>
          <DialogDescription>Copy this secret now. Relay Everything shows it once.</DialogDescription>
        </DialogHeader>
        {secret !== null && <Secret secret={secret} />}
        <DialogFooter><Button type="button" onClick={() => setSecret(null)}>Done</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </Card>
}

/** Where Relay sends your data: each webhook, its state, and its actions. */
export function Webhooks() {
  const [hooks, setHooks] = useState<Webhook[] | 'loading' | 'failed'>('loading')
  // The server lists the kinds, so a new kind gets its tick and name here by itself. An older server lists none.
  const [kinds, setKinds] = useState<WebhookKind[]>([])
  const read = useCallback(() => {
    get<{ webhooks: Webhook[]; kinds?: WebhookKind[] }>('webhooks').then((value) => { setHooks(value.webhooks); setKinds(value.kinds ?? []) },
      () => setHooks('failed'))
  }, [])
  const names = new Map(kinds.map((kind) => [kind.id, kind.label.toLowerCase()]))
  useEffect(read, [read])
  const load = () => { setHooks('loading'); read() }
  // From the newest list, as two actions can answer in either order.
  const change = (next: (list: Webhook[]) => Webhook[]) => setHooks((now) => next(Array.isArray(now) ? now : []))
  const replace = (hook: Webhook) => change((list) => list.some((other) => other.id === hook.id) ? list.map((other) => other.id === hook.id ? hook : other) : [...list, hook])
  return <section className="grid gap-3" aria-label="Send to your database">
    <div className="flex flex-wrap items-center gap-2">
      <h2 className="grow">Send to your database</h2>
      {kinds.length > 0 && <AddWebhook kinds={kinds} onAdd={replace} />}
    </div>
    {hooks === 'loading' && <p className="text-muted-foreground">Loading webhooks…</p>}
    {hooks === 'failed' && <p role="alert" className="flex flex-wrap items-center gap-3">
      Webhooks could not be loaded.<Button type="button" variant="outline" size="sm" onClick={load}>Try again</Button>
    </p>}
    {Array.isArray(hooks) && (hooks.length === 0 ? <p className="text-muted-foreground">No webhooks yet. Add one to copy each new note to your own database.</p> :
      <div className="grid gap-3 lg:grid-cols-2">{hooks.map((hook) => <HookCard key={hook.id} hook={hook} names={names} onChange={replace}
        onRemove={() => change((list) => list.filter((other) => other.id !== hook.id))} />)}</div>)}
  </section>
}
