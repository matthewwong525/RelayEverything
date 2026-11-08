import { useState } from 'react'
import { CopyText } from '@/components/CopyText'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Failed } from './Failed'
import { send, useGet } from './read'

// The Email card: the person's secret notes address, which any mail makes a note, and the shared address for their
// sign-in email. app/worker/apps/relay/inbox/ answers; a server with no mail domain shows no card.
type EmailView = { on: boolean; address: string | null; shared: string | null }
type Inbox = { email: EmailView }
/** Email is on, so the server gave both addresses. */
type Addresses = { address: string; shared: string }

function NewAddress({ onMade }: { onMade: (view: Addresses) => void }) {
  const [error, setError] = useState('')
  const make = () => send<Inbox>('inbox/address', {}).then((made) => { setError(''); onMade(made.email as Addresses) },
    () => setError('A new address could not be made. Try again.'))
  return <>
    <AlertDialog>
      <AlertDialogTrigger asChild><Button type="button" variant="ghost" size="sm">New address</Button></AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Make a new address?</AlertDialogTitle>
          <AlertDialogDescription>Mail to your old address stops making notes at once. Change every mail rule and contact that uses it.</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={make}>New address</AlertDialogAction></AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
  </>
}

function Addresses({ first }: { first: Addresses }) {
  const [view, setView] = useState(first)
  return <Card className="grid gap-3 p-4">
    <div className="flex flex-wrap items-start gap-2">
      <Input readOnly value={view.address} aria-label="Your notes address" className="min-w-0 grow basis-64" />
      <div><CopyText text={view.address} label="Copy" shown /></div>
    </div>
    <div className="flex flex-wrap items-center gap-2">
      <span className="grow text-sm text-muted-foreground">Anything sent here becomes a note.</span>
      <NewAddress onMade={setView} />
    </div>
    <p className="text-sm text-muted-foreground wrap-anywhere">You can also write to {view.shared} from your sign-in email.</p>
    <p className="text-sm text-muted-foreground">Email is not sealed on the way. Don't send health or location details this way.</p>
  </Card>
}

/** The Email section, shown only when this server takes email. */
export function Inbox() {
  const [state, retry] = useGet<Inbox>('inbox')
  if (state.status === 'loading' || (state.status === 'ready' && !state.value.email.on) || (state.status === 'failed' && state.code === 503)) return null
  return <section className="grid gap-3" aria-label="Email">
    <h2>Email</h2>
    {state.status === 'failed' ? <Failed what="Your notes address" retry={retry} /> : <Addresses first={state.value.email as Addresses} />}
  </section>
}
