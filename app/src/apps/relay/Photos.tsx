import { useState } from 'react'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Failed } from './Failed'
import { post, useGet } from './read'

// How many photos the phones sent, and *Delete all photos*. The page never shows the photos: the AI reads them
// through the connector. app/worker/apps/relay/photos.ts answers.
const number = new Intl.NumberFormat()

const counted = (count: number) =>
  count === 0 ? 'No photos yet' : `${number.format(count)} photo${count === 1 ? '' : 's'} sent from your phones.`

function DeleteAll({ onDeleted }: { onDeleted: (error: string) => void }) {
  const [pending, setPending] = useState(false)
  const [open, setOpen] = useState(false)
  async function remove() {
    setPending(true)
    const error = await post('photos/delete', { confirm: 'delete' }).then(() => '', () => 'The photos could not be deleted. Try again.')
    setPending(false)
    setOpen(false)
    onDeleted(error)
  }
  return <AlertDialog open={open} onOpenChange={setOpen}>
    <AlertDialogTrigger asChild>
      <Button type="button" variant="destructive"
        className="border border-destructive bg-transparent text-destructive hover:bg-destructive/10 dark:bg-transparent">Delete all photos</Button>
    </AlertDialogTrigger>
    <AlertDialogContent>
      <AlertDialogHeader>
        <AlertDialogTitle>Delete all photos?</AlertDialogTitle>
        <AlertDialogDescription>This deletes every photo your phones sent, and your AI can't see them any more. Recordings, notes, health
          and places stay. You can't undo it.</AlertDialogDescription>
      </AlertDialogHeader>
      <AlertDialogFooter>
        <AlertDialogCancel disabled={pending}>Cancel</AlertDialogCancel>
        <AlertDialogAction disabled={pending} onClick={(event) => { event.preventDefault(); void remove() }}>Delete all photos</AlertDialogAction>
      </AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>
}

/** The photos card, above the devices: the count and *Delete all photos*. */
export function Photos() {
  const [photos, retry] = useGet<{ count: number }>('photos')
  const [error, setError] = useState('')
  const deleted = (message: string) => { setError(message); retry() }
  return <section className="grid gap-3" aria-label="Photos">
    <h2>Photos</h2>
    {photos.status === 'loading' && <p className="text-muted-foreground">Loading photos…</p>}
    {photos.status === 'failed' && <Failed what="Photos" retry={retry} />}
    {photos.status === 'ready' && <Card className="grid gap-3 p-4">
      <p>{counted(photos.value.count)}</p>
      <p className="text-sm text-muted-foreground">Your AI can see them. Turn photos off in the phone app's Settings.</p>
      {photos.value.count > 0 && <div><DeleteAll onDeleted={deleted} /></div>}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </Card>}
  </section>
}
