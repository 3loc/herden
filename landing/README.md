# Herden landing page

The public site at <https://herden.app>. Astro produces a static,
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
npm run render:og    # regenerate public/og.png with Chromium
npm run preview      # serve dist/ locally
```

## Layout

| Path | What it holds |
| --- | --- |
| `src/pages/index.astro` | Public product page, setup commands and section layout. |
| `src/pages/ar.astro` | Even G2 simulator instructions, current hardware status and preview downloads. |
| `og-card.html` | Deterministic source for the 1200×630 social card. |
| `scripts/render-og-card.sh` | Renders `og-card.html` to `public/og.png`. |
| `public/install.sh` | Exact copy of the root Host installer, published at `/install.sh`. |
| `public/downloads/` | Versioned glasses simulator source and developer `.ehpk` artifacts. |
| `src/pages/404.astro` | Not-found page for unmatched paths. |
| `src/layouts/Layout.astro` | `<head>` metadata, header, footer, global CSS imports. |
| `src/components/*.astro` | One component per section, plus `Button`/`Badge`. |
| `src/styles/substrate/` | Vendored design system (see below). |
| `src/styles/landing.css` | Page skeleton: gutters, section rhythm, shared text roles. |
| `src/assets/` | Logo, fonts and the two current iPhone screenshots, optimised at build time. |

Keep the page compact: roughly one or two mobile screens, with the two phones
and smaller glasses together in the hero, followed by short setup instructions.
Use JetBrains Mono throughout. Do not expand this into a multi-section SaaS
landing page or move the glasses into a section far down the page.

## Design source

Copy changes should stay in sync with `README.md` at the repo root. The public
install block includes the one-session PATH export before the pairing step; the
installer also persists that directory for future shells. A piped child cannot
alter its parent shell's environment. See `../docs/guides/install-host.md`.

`src/styles/substrate/` is a vendored design-system snapshot, trimmed to what
this page renders: every token file plus the
Button and Badge rules from `components/core/core.css`. Re-sync those files from
the maintained design source rather than editing them; page-specific CSS belongs in
`landing.css` or a component's `<style>` block.

The public page uses the app's bundled JetBrains Mono throughout. These local
assets are under the SIL Open Font License 1.1; no font service is required.

The hero screenshots come from the app's deterministic `--demo-screenshots`
fixture. Its Hosts use `.demo.invalid` addresses and its Spaces and Agents are
privacy-safe sample data. Never publish a capture of real Spaces or project names.

The smaller AR glasses stay visible alongside both phones in the hero and link
to `/ar`. Their transparent artwork uses the real Even G2 simulator's generic
offline Space list. Source for that prototype currently lives in the sibling
`herden-glasses-hud` worktree. The AR page must distinguish the working desktop
demo from the unverified physical-glasses package and the not-yet-public Host
endpoint.

## Paper + Cobalt

The public site and native app share the same light and dark semantic palette.
Live Tether and primary controls use cobalt. Rust is reserved for attention,
green for success, and red for failure or destructive actions.

`logo.png` and `favicon.png` bake Live Tether into a rounded Paper tile.
`logo-light.svg` and `logo-dark.svg` provide appearance-specific transparent
marks for the header and footer.

| Token | Value | Use |
| --- | --- | --- |
| Canvas | `#FFFCF0` / `#100F0F` | Light and dark page backgrounds |
| Surface | `#F2F0E5` / `#1C1B1A` | Grouped and inset areas |
| Raised | `#FFFEF8` / `#282726` | Cards and overlapping objects |
| Ink | `#100F0F` / `#F2F0E5` | Primary text |
| Muted | `#575653` / `#B7B5AC` | Supporting text |
| Primary | `#205EA6` / `#4385BE` | Live Tether, controls and links |
| Attention | `#BC5215` / `#DA702C` | Pending, preview and recommended states |
| Success | `#5E6F00` / `#879A39` | Healthy and completed states only |

The complete palette and usage rules live in
[`docs/design/herden-paper-cobalt.md`](../docs/design/herden-paper-cobalt.md).

## Deployment

Deployment is intentionally absent from this repository. Operators own their
hosting, DNS, TLS, secrets and production verification separately.
