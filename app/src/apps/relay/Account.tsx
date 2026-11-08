import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { post, postTo, SIGN_IN, useMethods } from './read'
import { Contact } from './SignIn'

// The person's account: who is signed in, *Sign out*, *Delete my account*, which needs the email typed again, and the
// server's contact address when it has one.
const same = (one: string, other: string) => one.trim().toLowerCase() === other.trim().toLowerCase()

function DeleteAccount({ email, onDeleted }: { email: string; onDeleted: () => void }) {
  const [open, setOpen] = useState(false)
  const [typed, setTyped] = useState('')
  const [error, setError] = useState('')
  const remove = async () => {
    try {
      await post('account-delete', { email: typed.trim() })
      onDeleted()
    } catch (caught) { setError((caught as Error).message) }
  }
  return <Dialog open={open} onOpenChange={(next) => { setOpen(next); setTyped(''); setError('') }}>
    <DialogTrigger asChild><Button type="button" variant="destructive">Delete my account</Button></DialogTrigger>
    <DialogContent>
      <DialogHeader>
        <DialogTitle>Delete your account?</DialogTitle>
        <DialogDescription>This removes your notes, recordings, health, places, chats, devices, webhooks and connected AI apps. This can't be
          undone.</DialogDescription>
      </DialogHeader>
      <div className="grid gap-2"><Label htmlFor="delete-email">Type your email, {email}, to confirm</Label>
        <Input id="delete-email" type="email" autoComplete="off" value={typed} onChange={(event) => setTyped(event.target.value)} /></div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <DialogFooter>
        <Button type="button" variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
        <Button type="button" variant="destructive" disabled={!same(typed, email)} onClick={remove}>Delete everything</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
}

/** The bottom of the page: the account, sign-out, then deletion. `onSignedOut` shows the sign-in again. */
export function Account({ email, onSignedOut }: { email: string; onSignedOut: () => void }) {
  const [error, setError] = useState('')
  const methods = useMethods()
  const signOut = () => postTo(`${SIGN_IN}out`).then(onSignedOut, (caught: Error) => setError(caught.message))
  return <section className="grid gap-3" aria-label="Your account">
    <h2>Your account</h2>
    <Card className="grid gap-3 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="grow wrap-anywhere">Signed in as {email}</span>
        <Button type="button" variant="outline" onClick={signOut}>Sign out</Button>
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <div><DeleteAccount email={email} onDeleted={onSignedOut} /></div>
      <Contact methods={methods} />
    </Card>
  </section>
}
