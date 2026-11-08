import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { type Methods, postTo, SIGN_IN, useMethods } from './read'

// Relay Everything's own sign-in: a code sent by email, or Apple or Google. The same steps make a new account.
// app/worker/apps/relay/sign-in/ answers; on the company app Access signs people in, so it answers 404.

/** The page the AI connector asked to return to, only when it is one of Relay Everything's own. */
const nextOf = (value: string | null) => value?.startsWith('/apps/relay/') ? value : null

/** The server's line for questions and privacy requests, only when its owner set an address (RELAY_CONTACT_EMAIL). */
export function Contact({ methods }: { methods: Methods | 'loading' | 'none' }) {
  if (typeof methods !== 'object' || !methods.contact) return null
  return <p className="text-sm text-muted-foreground">Questions or privacy requests:{' '}
    <a className="underline wrap-anywhere" href={`mailto:${methods.contact}`}>{methods.contact}</a></p>
}

function CodeForm({ email, next, onSignedIn, onBack }: { email: string; next: string | null; onSignedIn: () => void; onBack: () => void }) {
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const signIn = async () => {
    try {
      await postTo(`${SIGN_IN}code`, { email, code })
      if (next) window.location.assign(next)
      else onSignedIn()
    } catch (caught) { setError((caught as Error).message) }
  }
  return <form className="grid gap-3" onSubmit={(event) => { event.preventDefault(); void signIn() }}>
    <p>We sent a code to <b className="wrap-anywhere">{email}</b>. It works for 10 minutes.</p>
    <div className="grid gap-2"><Label htmlFor="sign-in-code">Code</Label>
      <Input id="sign-in-code" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code}
        onChange={(event) => setCode(event.target.value.replace(/\D/g, ''))} /></div>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <Button type="submit" disabled={code.length !== 6}>Sign in</Button>
    <Button type="button" variant="ghost" onClick={onBack}>Use another email</Button>
  </form>
}

function EmailForm({ onSent }: { onSent: (email: string) => void }) {
  const [email, setEmail] = useState('')
  const [error, setError] = useState('')
  const send = async () => {
    try {
      await postTo(`${SIGN_IN}email`, { email: email.trim() })
      onSent(email.trim())
    } catch (caught) { setError((caught as Error).message) }
  }
  return <form className="grid gap-3" onSubmit={(event) => { event.preventDefault(); void send() }}>
    <div className="grid gap-2"><Label htmlFor="sign-in-email">Email</Label>
      <Input id="sign-in-email" type="email" autoComplete="email" placeholder="you@example.com" value={email}
        onChange={(event) => setEmail(event.target.value)} /></div>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <Button type="submit" disabled={!email.trim()}>Email me a code</Button>
  </form>
}

/** The sign-in screen, shown in place of the page while nobody is signed in. */
export function SignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const methods = useMethods()
  // The shared server's page has no router, so this reads the address itself.
  const params = new URLSearchParams(window.location.search)
  const [sentTo, setSentTo] = useState<string | null>(null)
  const next = nextOf(params.get('next'))
  const link = (provider: string) => `${SIGN_IN}${provider}${next ? `?next=${encodeURIComponent(next)}` : ''}`
  return <Card className="mx-auto grid w-full max-w-sm gap-4 p-6">
    <h1>Relay Everything</h1>
    {methods === 'loading' && <p className="text-muted-foreground">Loading…</p>}
    {methods === 'none' && <p>Sign in to see Relay Everything.</p>}
    {typeof methods === 'object' && <>
      <p className="text-muted-foreground">Sign in or make an account</p>
      {params.get('signIn') === 'failed' && <p role="alert" className="text-sm text-destructive">That sign-in did not work. Try again.</p>}
      {methods.apple && <Button asChild variant="ghost"><a href={link('apple')}>Continue with Apple</a></Button>}
      {methods.google && <Button asChild variant="ghost"><a href={link('google')}>Continue with Google</a></Button>}
      {methods.email && (methods.apple || methods.google) && <hr />}
      {methods.email && (sentTo === null ? <EmailForm onSent={setSentTo} />
        : <CodeForm email={sentTo} next={next} onSignedIn={onSignedIn} onBack={() => setSentTo(null)} />)}
      {methods.signUp && <p className="text-sm text-muted-foreground">New here? The same steps make your account.</p>}
      <Contact methods={methods} />
    </>}
  </Card>
}
