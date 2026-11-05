import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { ThemeToggle } from '@/components/ThemeToggle'
import { App } from './apps/relay/App'
import './index.css'

// The page of a Relay-only install (self-host/SETUP.md): the Relay app in a plain frame, and no WongStack shell.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <header className="sticky top-0 z-40 flex h-14 items-center border-b bg-background/80 backdrop-blur">
      <div className="mx-auto flex w-full max-w-[60rem] items-center justify-between gap-4 px-4">
        <span className="inline-flex items-center gap-2 font-semibold"><img className="h-auto w-8" src="/favicon.svg" alt="" />Relay</span>
        <ThemeToggle />
      </div>
    </header>
    <main className="mx-auto my-8 w-full max-w-[60rem] px-4"><App /></main>
  </StrictMode>,
)
