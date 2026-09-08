# Herden landing page

The public site at <https://herden.3loc.ltd>. Astro produces a static,
zero-client-JavaScript bundle. Production hosting configuration lives outside
this public product repository.

It is self-contained on purpose: nothing outside this directory imports from
it. Validate it locally with the commands below; GitHub Actions are
intentionally absent from this repository.

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
| `public/install.sh` | Exact copy of the root Host installer, published at `/install.sh`. |
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

Copy changes should stay in sync with `README.md` at the repo root.
Install blocks must retain the PATH export after `curl ... | sh`, so the next
`herden` command works in the same Terminal. The installer configures future
shells separately; see `../docs/guides/install-host.md`.

`src/styles/substrate/` is a vendored design-system snapshot, trimmed to what
this page renders: every token file plus the
Button and Badge rules from `components/core/core.css`. Re-sync those files from
the maintained design source rather than editing them; page-specific CSS belongs in
`landing.css` or a component's `<style>` block.

The Geist and Geist Mono variable fonts in
`src/styles/substrate/assets/fonts/` come from the `geist` npm package (SIL
Open Font License 1.1, `LICENSE.txt` alongside them).

The screenshots are copies of `docs/images/*.png` at the repo root, not
symlinks. Refresh them here when the app screenshots change.

## Deployment

Deployment is intentionally absent from this repository. Operators own their
hosting, DNS, TLS, secrets and production verification separately.
