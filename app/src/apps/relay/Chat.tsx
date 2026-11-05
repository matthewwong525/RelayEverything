import { useState } from 'react'
import { Loading } from '@/components/Loading'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Failed } from './Failed'
import { get, remove, useGet, when, type ChatMessage, type ChatPart } from './read'

// One saved chat as it happened: the AI's saves above, then each message, the AI's steps as muted single lines.
const WHO = { you: 'You', ai: 'AI' }

function Message({ message }: { message: ChatMessage }) {
  if (message.role === 'step') return <p className="text-sm text-muted-foreground wrap-anywhere">{message.text}</p>
  return <div className="grid gap-1">
    <span className="text-sm text-muted-foreground">{WHO[message.role]}</span>
    <p className="whitespace-pre-wrap wrap-anywhere">{message.text}</p>
  </div>
}

function Messages({ first, id }: { first: ChatPart; id: string }) {
  const [parts, setParts] = useState<ChatPart[]>([first])
  const [failed, setFailed] = useState(false)
  const { next } = parts.at(-1)!
  const more = async () => {
    try {
      const part = await get<ChatPart>(`chat?${new URLSearchParams({ id, after: String(next) })}`)
      setParts((done) => [...done, part])
      setFailed(false)
    } catch {
      setFailed(true)
    }
  }
  const { chat, saves } = first
  return <>
    <span className="text-sm text-muted-foreground">{[chat.project, when(chat.startedAt), 'Claude Code'].join(' · ')}</span>
    {saves.map((save) => <Card key={save.id} className="grid gap-2 border-dashed p-4" aria-label="Written by the AI">
      <div className="flex flex-wrap items-center gap-2"><Badge variant="outline">Written by the AI</Badge>
        <span className="text-sm text-muted-foreground">{save.title} · {when(save.createdAt)}</span></div>
      <p className="whitespace-pre-wrap wrap-anywhere">{save.text}</p>
    </Card>)}
    {parts.flatMap((part) => part.messages).map((message) => <Message key={message.seq} message={message} />)}
    {failed && <p role="alert">More messages could not be loaded.</p>}
    {next !== null && <Button type="button" variant="outline" className="justify-self-start" onClick={() => void more()}>Show more messages</Button>}
  </>
}

/** `close(true)` after a delete, so the list reads again. */
export function Chat({ id, close }: { id: string; close: (changed: boolean) => void }) {
  const [state, retry] = useGet<ChatPart>(`chat?${new URLSearchParams({ id })}`)
  const [confirming, setConfirming] = useState(false)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState('')
  async function erase() {
    setPending(true)
    const done = await remove(`chat?${new URLSearchParams({ id })}`).then(() => true, () => false)
    setPending(false)
    setConfirming(false)
    if (done) close(true)
    else setError('The chat could not be deleted. Try again.')
  }
  const title = state.status === 'ready' ? state.value.chat.title : 'Chat'
  return <Card className="grid gap-4 p-4">
    <div className="flex flex-wrap items-center gap-2">
      <Button type="button" variant="ghost" onClick={() => close(false)}>Back</Button>
      <h3 className="grow wrap-anywhere">{title}</h3>
      {state.status === 'ready' && <Button type="button" variant="ghost" className="text-destructive" onClick={() => { setError(''); setConfirming(true) }}>Delete</Button>}
    </div>
    {state.status === 'loading' && <Loading label="Loading the chat"><Skeleton className="h-32" /></Loading>}
    {state.status === 'failed' && <Failed what="The chat" retry={retry} />}
    {state.status === 'ready' && <Messages first={state.value} id={id} />}
    {error && <p role="alert">{error}</p>}
    <AlertDialog open={confirming} onOpenChange={setConfirming}>
      <AlertDialogContent className="wrap-anywhere">
        <AlertDialogHeader>
          <AlertDialogTitle>Delete {title}?</AlertDialogTitle>
          <AlertDialogDescription>Relay removes the chat, its messages and the AI's summary. You can't undo it.</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Cancel</AlertDialogCancel>
          <AlertDialogAction variant="destructive" disabled={pending} onClick={(event) => { event.preventDefault(); void erase() }}>Delete</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </Card>
}
