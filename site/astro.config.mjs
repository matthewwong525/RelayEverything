// The public Relay website: wiki/relay-website.md.
import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import { sidebar } from './sidebar.mjs';

export default defineConfig({
  site: 'https://relayeverything.com',
  output: 'static',
  integrations: [starlight({
    title: 'Relay Everything',
    description: 'Relay Everything gets your notes, health and location off your phone, into a place you choose, where your own AI can read them.',
    // The Relay Everything mark, brand/mark.svg in the light and dark accent: wiki/brand.md.
    logo: { light: './src/assets/relay-mark.svg', dark: './src/assets/relay-mark-dark.svg' },
    customCss: ['./src/styles/custom.css'],
    social: [{ icon: 'github', label: 'Relay Everything on GitHub', href: 'https://github.com/matthewwong525/RelayEverything' }],
    sidebar,
  })],
});
