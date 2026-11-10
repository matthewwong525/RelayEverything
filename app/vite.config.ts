import { fileURLToPath } from 'node:url'
import { defineConfig, searchForWorkspaceRoot, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

import { cloudflare } from "@cloudflare/vite-plugin";

const bootstrap = fileURLToPath(new URL('../scripts/employee-bootstrap.mjs', import.meta.url))

// The Relay Everything server (app/self-host/SETUP.md) serves the page in public/apps/relay/; its index.html only sends
// an unknown address there. RELAY_CONFIG names the install's config; a check uses the template.
const relayOnly: Plugin = { name: 'relay-only', transformIndexHtml: { order: 'pre', handler: () => '<!doctype html><html lang="en">' +
  '<head><meta charset="UTF-8" /><meta http-equiv="refresh" content="0; url=/apps/relay/" /><title>Relay Everything</title></head>' +
  '<body><a href="/apps/relay/">Open Relay Everything</a></body></html>' } }
const relayConfig = process.env.RELAY_CONFIG ?? './self-host/wrangler.template.jsonc'
// The spaces Worker bundles its migrations as text, as Wrangler's Text rule does on a deploy.
const sqlText: Plugin = { name: 'sql-text', transform: (code, id) => id.endsWith('.sql') ? `export default ${JSON.stringify(code)};` : undefined }

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => mode === 'relay-only' ? {
  plugins: [relayOnly, cloudflare({ configPath: relayConfig })],
  build: { outDir: 'dist-relay' },
} : {
  // Local dev runs the live line's and the spaces' Workers beside the app; a build leaves them out.
  plugins: [react(), tailwindcss(), sqlText, cloudflare(command === 'serve'
    ? { auxiliaryWorkers: [{ configPath: './wrangler.line.jsonc' }, { configPath: './wrangler.spaces.jsonc' }] } : {})],
  // `@/` is app/src/, the address the ready-made parts import each other by.
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  // The dev server reads one file outside app/: the setup script setup-file.ts imports, which a build bundles anyway.
  // Vite checks a `?raw` import's id as well as its path, so both are listed.
  ...(command === 'serve' && { server: { fs: { allow: [searchForWorkspaceRoot(process.cwd()), bootstrap, `${bootstrap}?raw`] } } }),
})
