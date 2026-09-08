// @ts-check
import { defineConfig } from 'astro/config';

// Static output only. Production hosting configuration lives outside this
// repository.
export default defineConfig({
  site: 'https://herden.3loc.ltd',
  build: {
    // Emit `/404.html` rather than `/404/index.html` so Workers' asset router
    // serves it as the not-found page.
    format: 'file',
  },
});
