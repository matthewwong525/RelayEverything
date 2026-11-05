// The docs menu, in reading order. tests/site.test.mjs checks each entry opens a built page.
const soon = { text: 'Soon', variant: 'default' };

export const sidebar = [
  { label: 'Get started', items: [
    { label: 'What you need', slug: 'start/what-you-need' },
    { label: 'Install the app', slug: 'start/install' },
    { label: 'Connect a phone', slug: 'start/connect-a-phone' },
    { label: 'Set up the Pebble webhook', slug: 'start/pebble-webhook' },
  ] },
  { label: 'Use the app', items: ['app/your-notes', 'app/health', 'app/location', 'app/settings'] },
  { label: 'Connections', items: [
    { label: 'Your own database', link: '/connections/#your-own-database', badge: soon },
    'connections/connect-your-ai',
    'connections/claude-code',
    { label: 'Example skill and tables', link: '/connections/#an-example-skill-and-tables', badge: soon },
  ] },
  { label: 'Server API', items: ['api/keys', 'api/reference', 'api/pebble-webhook', 'api/recordings'] },
  { label: 'The ring', items: ['ring/how-it-works', 'ring/parts-and-battery', 'ring/board', 'ring/models'] },
  { label: 'About', items: ['privacy'] },
];
