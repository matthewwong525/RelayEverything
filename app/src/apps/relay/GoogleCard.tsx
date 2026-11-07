import { useState } from 'react'
import { Failed } from './Failed'
import { send, useGet, when } from './read'
import { Loading } from '@/components/Loading'
import { Skeleton } from '@/components/ui/skeleton'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog'

// Google on Relay Everything's page: connect Gmail, Calendar, Drive and Contacts for the AI apps and API keys, or
// disconnect with a confirm. app/worker/apps/relay/google/connect.ts answers; wiki/stack/relay-google.md tells how.
type Connection = { email: string; scopes: string[]; connectedAt: number }
type GoogleState = { available: boolean; connected: Connection | null }

const CONNECT = '/apps/relay/google/connect'
const BACK: Record<string, string> = {
  missing: 'Allow Gmail, Calendar, Drive and Contacts to connect.',
  failed: 'Google could not be connected. Try again.',
}

/** Why the person came back from Google, read once; the address loses it so a reload doesn't show it again. */
function cameBack(): string {
  const url = new URL(window.location.href)
  const outcome = url.searchParams.get('google') ?? ''
  if (!outcome) return ''
  url.searchParams.delete('google')
  window.history.replaceState(null, '', url)
  return BACK[outcome] ?? ''
}

function Connected({ value, changed }: { value: Connection; changed: () => void }) {
  const [leaving, setLeaving] = useState(false)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState('')
  async function disconnect() {
    setPending(true)
    const done = await send('google-disconnect', {}).then(() => true, () => false)
    setPending(false)
    setLeaving(false)
    if (done) changed()
    else setError('Google could not be disconnected. Try again.')
  }
  return <>
    <div className="flex flex-wrap items-center justify-between gap-2">
      <span className="flex items-center gap-2 wrap-anywhere"><Badge variant="secondary">Connected</Badge>{value.email}</span>
      <Button type="button" variant="ghost" size="sm" onClick={() => { setError(''); setLeaving(true) }}>Disconnect</Button>
    </div>
    <p className="text-sm text-muted-foreground">Gmail, Calendar, Drive and Contacts, connected {when(value.connectedAt)}.</p>
    {error && <p role="alert">{error}</p>}
    <AlertDialog open={leaving} onOpenChange={setLeaving}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Disconnect Google?</AlertDialogTitle>
          <AlertDialogDescription>Your AI apps and API keys can't reach your email, calendar, files or contacts any more. To use them again, connect Google again.</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Cancel</AlertDialogCancel>
          <AlertDialogAction disabled={pending} onClick={(event) => { event.preventDefault(); void disconnect() }}>Disconnect</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </>
}

/** The Google section, below the AI apps. Hidden on a server with no Google client. */
export function GoogleCard() {
  const [state, retry] = useGet<GoogleState>('google')
  const [notice] = useState(cameBack)
  if (state.status === 'ready' && !state.value.available) return null
  return <section className="grid gap-3" aria-label="Google">
    <h2>Google</h2>
    {state.status === 'loading' && <Loading label="Loading Google"><Skeleton className="h-24" /></Loading>}
    {state.status === 'failed' && <Failed what="Google" retry={retry} />}
    {state.status === 'ready' && <Card className="grid gap-4 p-4">
      <p>Let your AI apps and API keys read and send your email, and reach your calendar, Drive files and contacts. Relay Everything keeps none of them.</p>
      {state.value.connected ? <Connected value={state.value.connected} changed={retry} /> : <>
        {notice && <p role="status">{notice}</p>}
        <div><Button asChild><a href={CONNECT}>Connect Google</a></Button></div>
      </>}
    </Card>}
  </section>
}
