import { useCallback, useEffect, useState } from 'react'

// Relay's own routes, read in the shapes app/worker/apps/relay/ writes.
export type Place = { lat: number; lon: number; accuracy: number | null; name: string | null; from: 'phone' | 'history' }
export type Note = { id: string; source: 'ring' | 'typed'; text: string; recordedAt: number; device: string; audio: boolean; place: Place | null }
export type Timeline = { notes: Note[]; next: number | null; nextId: string | null }
export type Summary = {
  day: string; notes: number; steps: number; sleepMinutes: number
  heartRate: { min: number; max: number; average: number } | null
  workouts: { count: number; minutes: number }
  places: { name: string; lat: number; lon: number; from: number; to: number }[]
}

type Attempt = { at: number; type: string; status: number | null; ms: number; error: string | null; first: number | null; last: number | null }
export type Webhook = {
  id: string; name: string; url: string; kinds: ('notes' | 'health' | 'locations')[]
  state: 'working' | 'paused' | 'failing' | 'backfilling'; waiting: number
  lastStatus: number | null; lastError: string | null; lastSentAt: number | null; nextTryAt: number | null; failingSince: number | null
  createdAt: number; attempts: Attempt[]
}

export const API = '/apps/relay/api/'

/** A route's refusal, with its status: 503 says the route's service is not set up here. */
class Refused extends Error {
  status: number
  constructor(route: string, status: number) {
    super(`${route}: ${status}`)
    this.status = status
  }
}

async function json<T>(route: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${route}`, init)
  if (!response.ok) throw new Refused(route, response.status)
  return await response.json() as T
}

/** A POST to one route, answered with its JSON; a refusal throws with the route's own message. */
export async function post<T>(route: string, input: object = {}): Promise<T> {
  const response = await fetch(`${API}${route}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(input) })
  const json = await response.json().catch(() => null) as { error?: { message?: string } } | null
  if (!response.ok) throw new Error(json?.error?.message ?? `${route}: ${response.status}`)
  return json as T
}

/** One route's JSON, or a Refused naming its address when the answer is not one. */
export const get = <T>(route: string) => json<T>(route)

/** A change sent as JSON, answered as JSON. */
export const send = <T>(route: string, body: unknown) =>
  json<T>(route, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })

/** Today in this browser's time zone, as the summary route takes it. */
export function today(now = new Date()) {
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000)
  return { day: local.toISOString().slice(0, 10), offset: -now.getTimezoneOffset() }
}

/** `code` is the refusal's status, or null when no answer came. */
type State<T> = { status: 'loading' } | { status: 'failed'; code: number | null } | { status: 'ready'; value: T }

/** A route read once the page opens, and again on `retry`. */
export function useGet<T>(route: string): [State<T>, () => void] {
  const [round, setRound] = useState(0)
  const [state, setState] = useState<State<T> & { round: number }>({ status: 'loading', round: 0 })
  useEffect(() => {
    let open = true
    get<T>(route).then(
      (value) => open && setState({ status: 'ready', value, round }),
      (error) => open && setState({ status: 'failed', code: error instanceof Refused ? error.status : null, round }),
    )
    return () => { open = false }
  }, [route, round])
  const retry = useCallback(() => setRound((value) => value + 1), [])
  return [state.round === round ? state : { status: 'loading' }, retry]
}

/** A time as the page shows it: the hour alone today, with the date on another day. */
export function when(ms: number, now = Date.now()) {
  const date = new Date(ms)
  const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
  return new Date(now).toDateString() === date.toDateString() ? time : `${date.toLocaleDateString([], { month: 'short', day: 'numeric' })}, ${time}`
}

/** Where a note was taken: the phone's place name, or its coordinates. */
export const where = (place: Place | null) =>
  place === null ? null : place.name ?? `${place.lat.toFixed(4)}, ${place.lon.toFixed(4)}`
