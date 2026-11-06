import { useState } from 'react'
import { CopyText } from '@/components/CopyText'
import { Loading } from '@/components/Loading'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Failed } from './Failed'
import { send, useGet, when } from './read'

// The AI connector on Relay's page: the address to add to Claude or ChatGPT, and the apps connected to it, each one
// disconnected with a confirm. app/worker/apps/relay/ai-apps.ts answers; wiki/stack/relay-ai-connector.md tells how.
type AiApp = { id: string; name: string; connectedAt: number }
type AiApps = { address: string; apps: AiApp[] }

function Connected({ value, changed }: { value: AiApps; changed: () => void }) {
  const [leaving, setLeaving] = useState<AiApp | null>(null)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState('')
  async function disconnect(app: AiApp) {
    setPending(true)
    const done = await send('ai-apps-disconnect', { id: app.id }).then(() => true, () => false)
    setPending(false)
    setLeaving(null)
    if (done) changed()
    else setError(`${app.name} could not be disconnected. Try again.`)
  }
  return <Card className="grid gap-4 p-4">
    <p>Ask Claude or ChatGPT about your notes, health and places. In the app, add a custom connector with this address, then sign in.</p>
    <div className="flex flex-wrap items-start gap-2">
      <Input readOnly value={value.address} aria-label="The connector's address" className="min-w-0 grow basis-64" />
      <div><CopyText text={value.address} label="Copy" shown /></div>
    </div>
    <div className="flex items-center gap-2"><h3>Connected apps</h3><Badge variant="secondary">{value.apps.length} connected</Badge></div>
    {value.apps.length === 0 ? <p className="text-muted-foreground">No AI app connected yet.</p> :
      <ul className="grid gap-2">{value.apps.map((app) => <li key={app.id} className="flex flex-wrap items-center justify-between gap-2">
        <span className="wrap-anywhere">{app.name}</span>
        <span className="flex items-center gap-2 text-sm text-muted-foreground">Connected {when(app.connectedAt)}
          <Button type="button" variant="ghost" size="sm" onClick={() => { setError(''); setLeaving(app) }}>Disconnect</Button>
        </span>
      </li>)}</ul>}
    {error && <p role="alert">{error}</p>}
    <AlertDialog open={leaving !== null} onOpenChange={() => setLeaving(null)}>
      <AlertDialogContent className="wrap-anywhere">
        <AlertDialogHeader>
          <AlertDialogTitle>Disconnect {leaving?.name}?</AlertDialogTitle>
          <AlertDialogDescription>It can't read Relay Everything any more. To use it again, connect it again from the app.</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Cancel</AlertDialogCancel>
          <AlertDialogAction disabled={pending} onClick={(event) => { event.preventDefault(); void disconnect(leaving!) }}>Disconnect</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </Card>
}

/** The AI apps section, below the notes. */
export function AiCard() {
  const [state, retry] = useGet<AiApps>('ai-apps')
  return <section className="grid gap-3" aria-label="AI apps">
    <h2>AI apps</h2>
    {state.status === 'loading' && <Loading label="Loading AI apps"><Skeleton className="h-32" /></Loading>}
    {state.status === 'failed' && (state.code === 503 ?
      <p className="text-muted-foreground">The AI connector is not set up here yet.</p> : <Failed what="The AI apps" retry={retry} />)}
    {state.status === 'ready' && <Connected value={state.value} changed={retry} />}
  </section>
}
