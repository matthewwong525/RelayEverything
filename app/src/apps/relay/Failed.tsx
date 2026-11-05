import { Button } from '@/components/ui/button'

/** A part of the page that could not be read, with a button to read it again. */
export function Failed({ what, retry }: { what: string; retry: () => void }) {
  return <p role="alert" className="flex flex-wrap items-center gap-3">
    {what} could not be loaded.
    <Button type="button" variant="outline" size="sm" onClick={retry}>Try again</Button>
  </p>
}
