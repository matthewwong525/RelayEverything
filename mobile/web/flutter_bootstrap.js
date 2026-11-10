{{flutter_js}}
{{flutter_build_config}}

// The fonts for emoji and other scripts come from this server, not Google: scripts/build-relay-web.mjs puts them in
// fallback-fonts/. No service worker: the browser keeps nothing of the page.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: new URL('fallback-fonts/', document.baseURI).href,
  },
});
