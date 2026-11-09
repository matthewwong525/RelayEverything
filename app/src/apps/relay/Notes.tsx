import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { API, get, sizeOf, when, where, type Note, type NoteFile, type Timeline } from './read'

/** One file: a picture in the note, any other file as a link that downloads it, or its name while it is on its way. */
function FileItem({ file }: { file: NoteFile }) {
  const label = `${file.name} · ${sizeOf(file.size)}`
  const src = `${API}attachment?id=${encodeURIComponent(file.id)}`
  if (!file.ready) return <Badge variant="outline">{label} · Waiting for the file</Badge>
  if (file.type.startsWith('image/')) {
    return <a href={src} target="_blank" rel="noreferrer"><img src={src} alt={file.name} loading="lazy" className="h-24 rounded-md border object-cover" /></a>
  }
  return <a href={src} download={file.name} className="text-sm underline underline-offset-4">{label} · Download</a>
}

function NoteCard({ note }: { note: Note }) {
  const place = where(note.place)
  return <Card className="grid gap-2 p-4" aria-label="Note">
    <span className="text-sm text-muted-foreground">{[when(note.recordedAt), place, note.device].filter(Boolean).join(' · ')}</span>
    {(note.text || !note.attachments.length) && <p className="wrap-anywhere">{note.text || <span className="text-muted-foreground">No words, only the recording.</span>}</p>}
    {note.audio && <audio controls preload="none" className="w-full" src={`${API}audio?id=${note.id}`} aria-label="The recording" />}
    {note.attachments.length > 0 && <ul className="flex flex-wrap items-center gap-2" aria-label="Files">
      {note.attachments.map((file) => <li key={file.id}><FileItem file={file} /></li>)}
    </ul>}
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
    {notes.length === 0 && <p className="text-muted-foreground">No notes yet. Write one in the Relay Everything app.</p>}
    {failed && <p role="alert">Older notes could not be loaded.</p>}
    {next !== null && <Button type="button" variant="outline" className="justify-self-start" onClick={() => void more()}>Show older notes</Button>}
  </section>
}
