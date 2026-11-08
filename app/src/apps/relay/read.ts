import { useCallback, useEffect, useRef, useState } from 'react'

// Relay's own routes, read in the shapes app/worker/apps/relay/ writes.
export type Place = { lat: number; lon: number; accuracy: number | null; name: string | null; from: 'phone' | 'history' }
/** A note's file: `ready` once the phone has sent it. */
export type NoteFile = { id: string; name: string; type: string; size: number; ready: boolean }
export type Note = {
  id: string; source: 'ring' | 'typed'; text: string; recordedAt: number; device: string; audio: boolean; place: Place | null
  attachments: NoteFile[]
}
export type Timeline = { notes: Note[]; next: number | null; nextId: string | null }
export type Summary = {
  day: string; notes: number; steps: number; sleepMinutes: number
  heartRate: { min: number; max: number; average: number } | null
  workouts: { count: number; minutes: number }
  /** The other health values: each only when the day has some. */
  weightKg?: number; restingHeartRate?: number; hrvSdnn?: number; hrvRmssd?: number
  bloodOxygen?: { min: number; average: number }; bloodPressure?: { at: number; upper: number; lower: number }[]
  cycleFlow?: number; mindfulMinutes?: number; waterMl?: number
  places: { name: string; lat: number; lon: number; from: number; to: number }[]
  events: { title: string; start: number; end: number; allDay: boolean; people: string[] }[]
}

export type ChatSummary = { id: string; title: string; project: string; app: 'claude-code'; startedAt: number; lastAt: number; messages: number; savedByAi: boolean }
export type ChatList = { chats: ChatSummary[]; next: number | null; nextId: string | null }
type ChatSave = { id: string; title: string; text: string; createdAt: number }
export type ChatMessage = { seq: number; role: 'you' | 'ai' | 'step'; text: string; at: number }
export type ChatPart = { chat: ChatSummary; saves: ChatSave[]; messages: ChatMessage[]; next: number | null }
type Attempt = { at: number; type: string; status: number | null; ms: number; error: string | null; first: number | null; last: number | null }
/** A kind of data a webhook can take, as the server lists it for the form's ticks and the card. */
export type WebhookKind = { id: string; label: string; detail: string; always: boolean; sensitive: boolean }
export type Webhook = {
  id: string; name: string; url: string; kinds: string[]
  state: 'working' | 'paused' | 'failing' | 'backfilling'; waiting: number
  lastStatus: number | null; lastError: string | null; lastSentAt: number | null; nextTryAt: number | null; failingSince: number | null
  createdAt: number; attempts: Attempt[]
}

export const API = '/apps/relay/api/'
export const SIGN_IN = '/apps/relay/sign-in/'

/** The ways in that the server has set up, and its contact address when it has one: sign-in/email.ts `methods`. */
export type Methods = { email: boolean; apple: boolean; google: boolean; signUp: boolean; contact?: string }

/** The server's sign-in methods, or `none` where Access signs people in and the route answers 404. */
export function useMethods() {
  const [methods, setMethods] = useState<Methods | 'loading' | 'none'>('loading')
  useEffect(() => {
    fetch(`${SIGN_IN}methods`).then(async (response): Promise<Methods | 'none'> => response.ok ? await response.json() as Methods : 'none')
      .then(setMethods, () => setMethods('none'))
  }, [])
  return methods
}
/** The page's own event when a route answers 401: the session ended, so the page shows the sign-in again. */
export const SIGNED_OUT = 'relay-signed-out'

const signedOut = (path: string, status: number) => {
  if (status === 401 && path.startsWith(API)) window.dispatchEvent(new Event(SIGNED_OUT))
}

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
  signedOut(API, response.status)
  if (!response.ok) throw new Refused(route, response.status)
  return await response.json() as T
}

/** A POST to one address, answered with its JSON; a refusal throws with the server's own message. */
export async function postTo<T>(path: string, input: object = {}, name = path): Promise<T> {
  const response = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(input) })
  signedOut(path, response.status)
  const json = await response.json().catch(() => null) as { error?: { message?: string } } | null
  if (!response.ok) throw new Error(json?.error?.message ?? `${name}: ${response.status}`)
  return json as T
}

/** A POST to one of the app's routes. */
export const post = <T>(route: string, input: object = {}) => postTo<T>(`${API}${route}`, input, route)

/** One route's JSON, or a Refused naming its address when the answer is not one. */
export const get = <T>(route: string) => json<T>(route)

/** A change sent as JSON, answered as JSON. */
export const send = <T>(route: string, body: unknown) =>
  json<T>(route, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })

/** A delete, answered as JSON. */
export const remove = <T>(route: string) => json<T>(route, { method: 'DELETE' })

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

/** A file's size as the page shows it, such as 240 KB or 1.2 MB. */
export function sizeOf(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

/** Scrolls once to `#id` when the page opened there, as the phone's *AI apps* and *Webhooks* rows do: the browser's
 *  own jump finds nothing yet. It waits for `ready`, so placeholders above it don't push the section down after. */
export function useOpenedAt(id: string, ready = true) {
  const done = useRef(false)
  useEffect(() => {
    if (!ready || done.current) return
    done.current = true
    if (window.location.hash === `#${id}`) document.getElementById(id)?.scrollIntoView?.()
  }, [id, ready])
}
