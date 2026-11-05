import { Loading } from '@/components/Loading'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Notes } from './Notes'
import { today, useGet, when, type Summary, type Timeline } from './read'
import { PebbleSetup, PhoneSetup } from './Setup'
import { Webhooks } from './Webhooks'

// Relay's site page: today's summary, every note with its place and recording, the places visited, and the webhooks
// that copy them to your own database. Phones and the Pebble app send to app/worker/apps/relay/.
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
      {places.length === 0 ? <p className="text-muted-foreground">No places yet today. Turn on location history in the Relay app.</p> :
        <Card className="grid gap-2 p-4">{places.map((place) => <div key={place.from} className="flex flex-wrap justify-between gap-2">
          <span className="wrap-anywhere">{place.name}</span>
          <span className="text-sm text-muted-foreground">{when(place.from)}{place.to > place.from && ` to ${when(place.to)}`}</span>
        </div>)}</Card>}
    </section>
  </>
}

function Failed({ what, retry }: { what: string; retry: () => void }) {
  return <p role="alert" className="flex flex-wrap items-center gap-3">
    {what} could not be loaded.
    <Button type="button" variant="outline" size="sm" onClick={retry}>Try again</Button>
  </p>
}

export function App() {
  const { day, offset } = today()
  const [summary, retrySummary] = useGet<Summary>(`summary?day=${day}&offset=${offset}`)
  const [timeline, retryTimeline] = useGet<Timeline>('timeline')
  const origin = window.location.origin
  return <div className="grid gap-6">
    <div className="flex flex-wrap items-center gap-2">
      <h1 className="grow">Relay</h1>
      <PhoneSetup origin={origin} />
      <PebbleSetup origin={origin} />
    </div>
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
    <Webhooks />
  </div>
}
