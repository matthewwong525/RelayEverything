import { fileURLToPath } from 'node:url'
import { defineConfig, searchForWorkspaceRoot, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

import { cloudflare } from "@cloudflare/vite-plugin";

const bootstrap = fileURLToPath(new URL('../scripts/employee-bootstrap.mjs', import.meta.url))

// A Relay-only install (self-host/SETUP.md) builds the same index.html around src/relay-only.tsx, with the install's
// own config; RELAY_CONFIG is the filled copy setup.mjs writes, and the template stands in for a check's build.
const relayOnly: Plugin = { name: 'relay-only', transformIndexHtml: { order: 'pre',
  handler: html => html.replace('/src/main.tsx', '/src/relay-only.tsx').replace('<title>Your apps</title>', '<title>Relay Everything</title>') } }
const relayConfig = process.env.RELAY_CONFIG ?? '../self-host/wrangler.template.jsonc'
// The spaces Worker bundles its migrations as text, as Wrangler's Text rule does on a deploy.
const sqlText: Plugin = { name: 'sql-text', transform: (code, id) => id.endsWith('.sql') ? `export default ${JSON.stringify(code)};` : undefined }

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => mode === 'relay-only' ? {
  plugins: [react(), tailwindcss(), relayOnly, cloudflare({ configPath: relayConfig })],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
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
