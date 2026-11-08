import { useEffect, useState } from 'react'
import { Loading } from '@/components/Loading'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Chat } from './Chat'
import { ConnectClaude } from './ConnectClaude'
import { Failed } from './Failed'
import { get, useGet, when, type ChatList, type ChatSummary } from './read'

// Saved Claude Code chats on Relay's page: search, the list newest first, and one chat opened in place. The Relay
// plugin sends them with a chat key: app/worker/apps/relay/chats.ts.
const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? '' : 's'}`

function Row({ chat, open }: { chat: ChatSummary; open: () => void }) {
  return <li className="grid gap-1">
    <div className="flex flex-wrap items-center gap-2">
      <button type="button" className="grow text-left underline-offset-4 hover:underline wrap-anywhere" onClick={open}>{chat.title}</button>
      {chat.savedByAi && <Badge variant="secondary">Saved by the AI</Badge>}
    </div>
    <span className="text-sm text-muted-foreground">{[chat.project, when(chat.lastAt), plural(chat.messages, 'message')].join(' · ')}</span>
  </li>
}

function List({ first, query, open }: { first: ChatList; query: string; open: (id: string) => void }) {
  const [older, setOlder] = useState<ChatList[]>([])
  const [failed, setFailed] = useState(false)
  const pages = [first, ...older]
  const { next, nextId } = pages.at(-1)!
  const more = async () => {
    try {
      const page = await get<ChatList>(`chats?${new URLSearchParams({ q: query, before: String(next), beforeId: String(nextId) })}`)
      setOlder((done) => [...done, page])
      setFailed(false)
    } catch {
      setFailed(true)
    }
  }
  const chats = pages.flatMap((page) => page.chats)
  if (!chats.length) return <p className="text-muted-foreground">{query ? 'No chat holds those words.' :
    'No chats yet. Connect Claude Code, and each chat from then on is saved here.'}</p>
  return <Card className="grid gap-3 p-4">
    <ul className="grid gap-3">{chats.map((chat) => <Row key={chat.id} chat={chat} open={() => open(chat.id)} />)}</ul>
    {failed && <p role="alert">Older chats could not be loaded.</p>}
    {next !== null && <Button type="button" variant="outline" className="justify-self-start" onClick={() => void more()}>Show older chats</Button>}
  </Card>
}

/** The Chats section, below the notes. `onSettled` runs once the list's first read ends, as the page's scroll waits. */
export function Chats({ onSettled }: { onSettled: () => void }) {
  const [typed, setTyped] = useState('')
  const [query, setQuery] = useState('')
  const [opened, setOpened] = useState<string | null>(null)
  const [state, retry] = useGet<ChatList>(query ? `chats?${new URLSearchParams({ q: query })}` : 'chats')
  const closed = (changed: boolean) => { setOpened(null); if (changed) retry() }
  const settled = state.status !== 'loading'
  useEffect(() => { if (settled) onSettled() }, [settled, onSettled])
  return <section className="grid gap-3" aria-label="Chats">
    <div className="flex flex-wrap items-center gap-2"><h2 className="grow">Chats</h2><ConnectClaude /></div>
    {opened ? <Chat id={opened} close={closed} /> : <>
      <form role="search" onSubmit={(event) => { event.preventDefault(); setQuery(typed.trim()) }}>
        <Input type="search" placeholder="Search your chats" aria-label="Search your chats" value={typed} onChange={(event) => setTyped(event.target.value)} />
      </form>
      {state.status === 'loading' && <Loading label="Loading chats"><Skeleton className="h-24" /></Loading>}
      {state.status === 'failed' && <Failed what="Chats" retry={retry} />}
      {state.status === 'ready' && <List key={query} first={state.value} query={query} open={setOpened} />}
    </>}
  </section>
}
