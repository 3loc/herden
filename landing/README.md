# Herden landing page

The private site at <https://herden.austrheim.ca7.fm>. Astro produces a static,
zero-client-JavaScript bundle. The 3loc fleet serves it from nidavellir through
Traefik; Headscale is the remote access layer and there is no public WAN route.

It is self-contained on purpose: nothing outside this directory imports from
it, and no other workflow in the repo depends on it. `ci.yml` excludes
`landing/**` and `.github/workflows/landing.yml` only runs for it, so a copy
edit here never starts an iOS build.

## Commands

```bash
npm install          # once
npm run dev          # local dev server with hot reload
npm run check        # astro check (typechecks .astro templates)
npm run build        # static build into dist/
npm run preview      # serve dist/ locally
```

## Layout

| Path | What it holds |
| --- | --- |
| `src/pages/index.astro` | The page: composes the section components in order. |
| `src/pages/404.astro` | Not-found page for unmatched paths. |
| `src/layouts/Layout.astro` | `<head>` metadata, header, footer, global CSS imports. |
| `src/components/*.astro` | One component per section, plus `Button`/`Badge`. |
| `src/styles/substrate/` | Vendored design system (see below). |
| `src/styles/landing.css` | Page skeleton: gutters, section rhythm, shared text roles. |
| `src/assets/` | Logo and the six iPhone screenshots, optimised at build time. |

Breakpoints live with the component that needs them. The source design is
desktop-only. The responsive behaviour (header nav collapse, the screenshot
rail below 1060px, single-column grids on phones) was added here.

## Design source

The page is an implementation of `Herden Landing.dc.html` in the Claude Design
project [项目落地页制作](https://claude.ai/design/p/eebe1402-ef74-4c67-9a76-c8ca5d6124c6).
Copy changes should stay in sync with `README.md` at the repo root, which is
where the content came from.

`src/styles/substrate/` is the Substrate design system from that project
(`substrate-design-system-4f544429-9771-4068-8ef1-7d18a69e56c0`), vendored
verbatim but trimmed to what this page renders: every token file plus the
Button and Badge rules from `components/core/core.css`. Re-sync those files from
the design project rather than editing them; page-specific CSS belongs in
`landing.css` or a component's `<style>` block.

The Geist and Geist Mono variable fonts in
`src/styles/substrate/assets/fonts/` come from the `geist` npm package (SIL
Open Font License 1.1, `LICENSE.txt` alongside them).

The screenshots are copies of `docs/images/*.png` at the repo root, not
symlinks. Refresh them here when the app screenshots change.

## Deployment

GitHub Actions only typechecks and builds. Deployment is intentionally absent
from this repository: the fleet repository owns the nidavellir workload,
Traefik router, split-DNS alias, Headscale policy, secrets, and verification.
