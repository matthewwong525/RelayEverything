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

export const API = '/apps/relay/api/'

/** One route's JSON, or an error naming its address when the answer is not one. */
export async function get<T>(route: string): Promise<T> {
  const response = await fetch(`${API}${route}`)
  if (!response.ok) throw new Error(`${route}: ${response.status}`)
  return await response.json() as T
}

/** Today in this browser's time zone, as the summary route takes it. */
export function today(now = new Date()) {
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000)
  return { day: local.toISOString().slice(0, 10), offset: -now.getTimezoneOffset() }
}

type State<T> = { status: 'loading' } | { status: 'failed' } | { status: 'ready'; value: T }

/** A route read once the page opens, and again on `retry`. */
export function useGet<T>(route: string): [State<T>, () => void] {
  const [round, setRound] = useState(0)
  const [state, setState] = useState<State<T> & { round: number }>({ status: 'loading', round: 0 })
  useEffect(() => {
    let open = true
    get<T>(route).then(
      (value) => open && setState({ status: 'ready', value, round }),
      () => open && setState({ status: 'failed', round }),
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
