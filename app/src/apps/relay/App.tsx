import { useEffect, useState } from 'react'
import { Loading } from '@/components/Loading'
import { Card } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Account } from './Account'
import { AiCard } from './AiCard'
import { Chats } from './Chats'
import { Devices } from './Devices'
import { Failed } from './Failed'
import { GoogleCard } from './GoogleCard'
import { Notes } from './Notes'
import { SIGNED_OUT, today, useGet, when, type Summary, type Timeline } from './read'
import { SignIn } from './SignIn'
import { Webhooks } from './Webhooks'

// Relay Everything's page: the sign-in, then today's summary, notes, chats, webhooks, devices and the account. Devices
// send to app/worker/apps/relay/; this page reads the signed-in person's own space.
const number = new Intl.NumberFormat()

function Tile({ label, value }: { label: string; value: string }) {
  return <Card className="grid gap-1 p-4"><span className="text-sm text-muted-foreground">{label}</span><span className="text-2xl font-semibold">{value}</span></Card>
}

const hours = (minutes: number) => `${Math.floor(minutes / 60)} h ${minutes % 60} min`

function Day({ summary }: { summary: Summary }) {
  const { heartRate, workouts, places } = summary
  return <>
    <section className="grid grid-cols-2 gap-3 lg:grid-cols-4" aria-label="Today">
      <Tile label="Notes today" value={number.format(summary.notes)} />
      <Tile label="Steps" value={number.format(summary.steps)} />
      <Tile label="Sleep" value={summary.sleepMinutes ? hours(summary.sleepMinutes) : 'None yet'} />
      <Tile label="Places" value={number.format(places.length)} />
    </section>
    <p className="text-sm text-muted-foreground">
      {heartRate ? `Heart rate ${heartRate.min} to ${heartRate.max} bpm, ${heartRate.average} on average.` : 'No heart rate yet today.'}{' '}
      {workouts.count ? `${workouts.count} workout${workouts.count === 1 ? '' : 's'}, ${workouts.minutes} min.` : 'No workouts yet today.'}
    </p>
    <section className="grid gap-3" aria-label="Places">
      <h2>Places today</h2>
      {places.length === 0 ? <p className="text-muted-foreground">No places yet today. Turn on location history in the Relay Everything app.</p> :
        <Card className="grid gap-2 p-4">{places.map((place) => <div key={place.from} className="flex flex-wrap justify-between gap-2">
          <span className="wrap-anywhere">{place.name}</span>
          <span className="text-sm text-muted-foreground">{when(place.from)}{place.to > place.from && ` to ${when(place.to)}`}</span>
        </div>)}</Card>}
    </section>
  </>
}

function Home({ email, onSignedOut }: { email: string; onSignedOut: () => void }) {
  const { day, offset } = today()
  const [summary, retrySummary] = useGet<Summary>(`summary?day=${day}&offset=${offset}`)
  const [timeline, retryTimeline] = useGet<Timeline>('timeline')
  return <div className="grid gap-6">
    <h1>Relay Everything</h1>
    {summary.status === 'loading' && <Loading label="Loading today" className="grid grid-cols-2 gap-3 lg:grid-cols-4">
      {[1, 2, 3, 4].map((tile) => <Skeleton key={tile} className="h-20" />)}
    </Loading>}
    {summary.status === 'failed' && <Failed what="Today's summary" retry={retrySummary} />}
    {summary.status === 'ready' && <Day summary={summary.value} />}
    {timeline.status === 'loading' && <Loading label="Loading notes" className="grid gap-3">
      {[1, 2, 3].map((card) => <Skeleton key={card} className="h-24" />)}
    </Loading>}
    {timeline.status === 'failed' && <Failed what="Notes" retry={retryTimeline} />}
    {timeline.status === 'ready' && <Notes first={timeline.value} />}
    <Chats />
    <Webhooks />
    <AiCard />
    <GoogleCard />
    <Devices />
    <Account email={email} onSignedOut={onSignedOut} />
  </div>
}

export function App() {
  const [account, retry] = useGet<{ email: string }>('account')
  const [signedOut, setSignedOut] = useState(false)
  useEffect(() => {
    const out = () => setSignedOut(true)
    window.addEventListener(SIGNED_OUT, out)
    return () => window.removeEventListener(SIGNED_OUT, out)
  }, [])
  const signedIn = () => { setSignedOut(false); retry() }
  if (signedOut || (account.status === 'failed' && account.code === 401)) return <SignIn onSignedIn={signedIn} />
  if (account.status === 'failed') return <Failed what="Your account" retry={retry} />
  if (account.status === 'loading') return <Loading label="Loading Relay Everything" className="grid gap-3"><Skeleton className="h-24" /></Loading>
  return <Home email={account.value.email} onSignedOut={() => setSignedOut(true)} />
}
