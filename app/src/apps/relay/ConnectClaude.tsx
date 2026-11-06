import { Button } from '@/components/ui/button'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'

// How to send Claude Code chats here: a chat key, then the Relay plugin from the public repository.
const Code = ({ children }: { children: string }) => <code className="block rounded bg-muted px-2 py-1 wrap-anywhere">{children}</code>

export function ConnectClaude() {
  return <Dialog>
    <DialogTrigger asChild><Button type="button" variant="ghost">Connect Claude Code</Button></DialogTrigger>
    <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
      <DialogHeader>
        <DialogTitle>Connect Claude Code</DialogTitle>
        <DialogDescription>A connect code made for Claude Code can only add chats. It can't read, change or delete anything on the
          server, your chats included.</DialogDescription>
      </DialogHeader>
      <ol className="grid list-decimal gap-3 pl-5">
        <li>Make a connect code on the computer that holds Relay Everything's keys:
          <Code>node scripts/relay-device-key.mjs create --name "Laptop" --for claude-code</Code></li>
        <li>In Claude Code, add the plugin:
          <Code>/plugin marketplace add matthewwong525/RelayEverything</Code>
          <Code>/plugin install relay@relay</Code></li>
        <li>Paste the connect code when Claude Code asks.</li>
      </ol>
      <p className="text-sm text-muted-foreground">Chats from then on are saved. Older chats are not sent. Type <code>/relay:saving off</code> in a
        project to keep its chats out.</p>
      <p className="text-sm text-muted-foreground">To keep chats in your own account, run your own Relay Everything server and make the code there.</p>
      <DialogFooter><DialogClose asChild><Button type="button">Done</Button></DialogClose></DialogFooter>
    </DialogContent>
  </Dialog>
}
