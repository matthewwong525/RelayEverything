// The public Relay website: wiki/relay-website.md.
import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import { sidebar } from './sidebar.mjs';

export default defineConfig({
  site: 'https://relayeverything.com',
  output: 'static',
  integrations: [starlight({
    title: 'Relay',
    description: 'Relay gets your notes, health and location off your phone, into a place you choose, where your own AI can read them.',
    logo: { src: './src/assets/ring-mark.svg' },
    customCss: ['./src/styles/custom.css'],
    social: [{ icon: 'github', label: 'The app on GitHub', href: 'https://github.com/matthewwong525/relay-app' }],
    sidebar,
  })],
});
