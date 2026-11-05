import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { API, get, when, where, type Note, type Timeline } from './read'

function NoteCard({ note }: { note: Note }) {
  const place = where(note.place)
  return <Card className="grid gap-2 p-4" aria-label={`${note.source === 'ring' ? 'Ring' : 'Typed'} note`}>
    <div className="flex flex-wrap items-center gap-2">
      <Badge variant={note.source === 'ring' ? 'default' : 'outline'}>{note.source === 'ring' ? 'Ring' : 'Typed'}</Badge>
      <span className="text-sm text-muted-foreground">{[when(note.recordedAt), place, note.device].filter(Boolean).join(' · ')}</span>
    </div>
    <p className="wrap-anywhere">{note.text || <span className="text-muted-foreground">No words, only the recording.</span>}</p>
    {note.audio && <audio controls preload="none" className="w-full" src={`${API}audio?id=${note.id}`} aria-label="The recording" />}
  </Card>
}

/** The timeline: the first page from the page's read, then older pages on request. */
export function Notes({ first }: { first: Timeline }) {
  const [pages, setPages] = useState<Timeline[]>([first])
  const [failed, setFailed] = useState(false)
  const { next, nextId } = pages.at(-1)!
  const more = async () => {
    try {
      const page = await get<Timeline>(`timeline?${new URLSearchParams({ before: String(next), beforeId: String(nextId) })}`)
      setPages((done) => [...done, page])
      setFailed(false)
    } catch {
      setFailed(true)
    }
  }
  const notes = pages.flatMap((page) => page.notes)
  return <section className="grid gap-3" aria-label="Notes">
    <h2>Notes</h2>
    {notes.map((note) => <NoteCard key={note.id} note={note} />)}
    {notes.length === 0 && <p className="text-muted-foreground">No notes yet. Hold the ring and talk, or write one in the Relay app.</p>}
    {failed && <p role="alert">Older notes could not be loaded.</p>}
    {next !== null && <Button type="button" variant="outline" className="justify-self-start" onClick={() => void more()}>Show older notes</Button>}
  </section>
}
