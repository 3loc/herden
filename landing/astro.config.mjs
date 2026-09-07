// @ts-check
import { defineConfig } from 'astro/config';

// Static output only: the page is zero-JS and is served inside the 3loc
// tailnet by nidavellir's web workload behind Traefik.
export default defineConfig({
  site: 'https://herden.austrheim.ca7.fm',
  build: {
    // Emit `/404.html` rather than `/404/index.html` so Workers' asset router
    // serves it as the not-found page.
    format: 'file',
  },
});
