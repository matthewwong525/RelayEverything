import { fileURLToPath } from 'node:url'
import { defineConfig, searchForWorkspaceRoot, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

import { cloudflare } from "@cloudflare/vite-plugin";

const bootstrap = fileURLToPath(new URL('../scripts/employee-bootstrap.mjs', import.meta.url))

// A Relay-only install (self-host/SETUP.md) builds the same index.html around src/relay-only.tsx, with the install's
// own config; RELAY_CONFIG is the filled copy setup.mjs writes, and the template stands in for a check's build.
const relayOnly: Plugin = { name: 'relay-only', transformIndexHtml: { order: 'pre',
  handler: html => html.replace('/src/main.tsx', '/src/relay-only.tsx').replace('<title>Your apps</title>', '<title>Relay</title>') } }
const relayConfig = process.env.RELAY_CONFIG ?? '../self-host/wrangler.template.jsonc'

// https://vite.dev/config/
export default defineConfig(({ command, mode }) => mode === 'relay-only' ? {
  plugins: [react(), tailwindcss(), relayOnly, cloudflare({ configPath: relayConfig })],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  build: { outDir: 'dist-relay' },
} : {
  // Local dev runs the live line's Worker beside the app; a build leaves it out, and cf-build.sh bundles it.
  plugins: [react(), tailwindcss(), cloudflare(command === 'serve' ? { auxiliaryWorkers: [{ configPath: './wrangler.line.jsonc' }] } : {})],
  // `@/` is app/src/, the address the ready-made parts import each other by.
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  // The dev server reads one file outside app/: the setup script setup-file.ts imports, which a build bundles anyway.
  // Vite checks a `?raw` import's id as well as its path, so both are listed.
  ...(command === 'serve' && { server: { fs: { allow: [searchForWorkspaceRoot(process.cwd()), bootstrap, `${bootstrap}?raw`] } } }),
})
