// The docs menu, in reading order. tests/site.test.mjs checks each entry opens a built page.
const soon = { text: 'Soon', variant: 'default' };

export const sidebar = [
  { label: 'Get started', items: [
    { label: 'What you need', slug: 'start/what-you-need' },
    { label: 'Run your own server', slug: 'start/run-your-own' },
    { label: 'Sign up', slug: 'start/sign-up' },
    { label: 'Install the app', slug: 'start/install' },
    { label: 'Connect a phone', slug: 'start/connect-a-phone' },
  ] },
  { label: 'Use the app', items: ['app/your-notes', 'app/voice-notes', 'app/share', 'app/shortcuts', 'app/email', 'app/health', 'app/calendar', 'app/location', 'app/photos', 'app/settings'] },
  { label: 'Connections', items: [
    { label: 'Your own database', slug: 'connections/your-database' },
    'connections/connect-your-ai',
    'connections/claude-code',
    { label: 'Example skill and tables', link: '/connections/#an-example-skill-and-tables', badge: soon },
  ] },
  { label: 'Server API', items: ['api/keys', 'api/reference', 'api/recordings', 'api/files'] },
  { label: 'Web API', items: ['api/connect-a-service', 'api/v1-reference'] },
  { label: 'About', items: ['privacy'] },
];
