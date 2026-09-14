# Herden Paper + Cobalt

Status: implemented and released

Owner: Herden

Last updated: 13 September 2026

## Direction

Warm editor paper, serious cobalt controls, and rust only when something needs
attention.

Herden should feel like a well-made terminal tool that happens to have a native
interface. It should not look like a SaaS dashboard, a productivity template or
a neon hacker toy. The visual system takes its neutral logic and restraint from
[Flexoki](https://stephango.com/flexoki), then applies it to Herden's own
product roles.

This is an adaptation, not a claim that the product uses Flexoki unchanged.
Herden owns the semantic roles, typography, geometry and interaction rules.

## Character

Herden is:

- calm rather than soft;
- technical rather than futuristic;
- compact rather than dense;
- warm rather than beige;
- precise rather than polished for its own sake;
- native on iPhone and familiar to terminal users.

The interface should look useful before it looks impressive. Its signature is
the contrast between warm paper, inky type and one disciplined cobalt action
colour.

## Core rules

1. **Neutrals do most of the work.** Between 80 and 90 per cent of any screen
   should be paper, ink and the neutral ramp.
2. **Cobalt is identity and control.** Use it for the logo, primary actions,
   selection, links, focus and active Agent state.
3. **Rust is an attention signal.** Use it for waiting, preview, beta, pending,
   recommendations and other states that deserve a second look. It is not a
   decorative accent.
4. **Green means success only.** Green is no longer Herden's brand colour. It
   indicates a completed or healthy state.
5. **Red means failure or destructive action.** It is never used to add energy
   to a quiet screen.
6. **One strong action per view.** A screen may contain many controls, but only
   the most important next action receives a filled cobalt treatment.
7. **Structure comes from spacing and rules.** Use borders and alignment before
   cards, shadows or background changes.
8. **Light and dark are designed together.** Dark mode is not an inverted light
   palette. Cobalt, rust, green and red each use a lighter night value.

## Colour system

The names below describe roles, not literal pigments. Product code should use
the semantic names. Raw palette names such as `blue-600` must not leak into
views.

### Light appearance

| Token | Value | Use |
| --- | --- | --- |
| `canvas` | `#FFFCF0` | Main application and website background |
| `surface` | `#F2F0E5` | Grouped areas, input wells and quiet controls |
| `surface-raised` | `#FFFEF8` | Menus, sheets and the few elements that must lift from paper |
| `surface-pressed` | `#E6E4D9` | Pressed and selected neutral controls |
| `ink` | `#100F0F` | Primary text, icons and terminal-like blocks |
| `ink-muted` | `#575653` | Secondary text |
| `ink-subtle` | `#6F6E69` | Tertiary labels and metadata, never essential at tiny sizes |
| `border` | `#CECDC3` | Hairlines and control outlines |
| `border-strong` | `#B7B5AC` | Hovered, selected or structurally important outlines |
| `primary` | `#205EA6` | Brand mark, primary action, link, focus and active state |
| `primary-soft` | `rgba(32, 94, 166, 0.10)` | Selection wash and quiet active background |
| `attention` | `#BC5215` | Waiting, preview, recommendation and pending state |
| `attention-soft` | `rgba(188, 82, 21, 0.10)` | Attention wash |
| `success` | `#5E6F00` | Success text and icons |
| `success-soft` | `rgba(94, 111, 0, 0.10)` | Success wash |
| `fault` | `#AF3029` | Error, destructive action and recording failure |
| `fault-soft` | `rgba(175, 48, 41, 0.10)` | Error wash |

### Dark appearance

| Token | Value | Use |
| --- | --- | --- |
| `canvas` | `#100F0F` | Main application and website background |
| `surface` | `#1C1B1A` | Grouped areas, input wells and quiet controls |
| `surface-raised` | `#282726` | Menus, sheets and raised controls |
| `surface-pressed` | `#343331` | Pressed and selected neutral controls |
| `ink` | `#F2F0E5` | Primary text and icons |
| `ink-muted` | `#B7B5AC` | Secondary text |
| `ink-subtle` | `#878580` | Tertiary labels and metadata |
| `border` | `#403E3C` | Hairlines and control outlines |
| `border-strong` | `#575653` | Hovered, selected or structurally important outlines |
| `primary` | `#4385BE` | Brand mark, primary action, link, focus and active state |
| `primary-soft` | `rgba(67, 133, 190, 0.16)` | Selection wash and quiet active background |
| `attention` | `#DA702C` | Waiting, preview, recommendation and pending state |
| `attention-soft` | `rgba(218, 112, 44, 0.16)` | Attention wash |
| `success` | `#879A39` | Success text and icons |
| `success-soft` | `rgba(135, 154, 57, 0.16)` | Success wash |
| `fault` | `#D65A50` | Error, destructive action and recording failure |
| `fault-soft` | `rgba(214, 90, 80, 0.16)` | Error wash |

### Contrast contract

The important fixed pairs meet WCAG AA for normal text:

| Pair | Ratio |
| --- | ---: |
| Light `ink` on `canvas` | 18.62:1 |
| Light `ink-muted` on `canvas` | 7.14:1 |
| Light `primary` on `canvas` | 6.36:1 |
| Light `canvas` on `primary` | 6.36:1 |
| Dark `ink` on `canvas` | 16.74:1 |
| Dark `ink-muted` on `canvas` | 9.31:1 |
| Dark `primary` on `canvas` | 4.86:1 |
| Dark `canvas` on `primary` | 4.86:1 |
| Light `attention` on `canvas` | 4.69:1 |
| Dark `attention` on `canvas` | 5.77:1 |

Do not assume that a token is safe on every surface. In dark appearance, a
filled cobalt button uses `canvas` text, not pale text. Soft semantic washes
always keep `ink` or their tested solid semantic colour as the foreground.
Colour cannot be the only status cue. Pair it with a label, icon or change in
weight.

## Semantic states

| Product meaning | Colour | Required non-colour cue |
| --- | --- | --- |
| Selected Space | Cobalt | Selection bar, checkmark or stronger label |
| Agent working | Cobalt | `working` label and activity indicator |
| Agent waiting for input | Rust | `needs input` label |
| Preview or beta feature | Rust | `preview` or `beta` label |
| Paired, connected or completed | Green | Checkmark and explicit state |
| Disconnected but recoverable | Neutral | `offline` or `disconnected` label |
| Failed or destructive | Red | Error label, warning icon or destructive verb |

Rust must remain rare. If rust appears in the logo, navigation, primary button
and status badges at the same time, it has stopped communicating attention.

## Typography

Herden uses two typefaces in the product system:

- **Inter** for native application structure, prose, labels and touch controls.
  It carries the iOS interface because it remains clear at small sizes.
- **JetBrains Mono** for the public website, commands, Host addresses, Space and
  Agent names, state labels and terminal-adjacent metadata. On the landing page
  it is the voice, not a decorative code sample.

Instrument Serif is not part of this direction's core interface. It may be used
later for a genuinely editorial document, but it should not create an unrelated
luxury-editorial layer inside the app.

### Type behaviour

- Use sentence case for actions and navigation.
- Use uppercase only for short state labels and technical eyebrows.
- Keep display tracking tight, but never below `-0.05em` for JetBrains Mono.
- Keep body copy between 55 and 72 characters per line.
- Prefer 400 for prose, 600 for labels and 700 only for a primary headline or
  compact technical state.
- Commands, paths and identifiers remain monospace even inside the native app.

## Layout and component language

### Geometry

- Base spacing unit: 4 pt on iOS and 4 px on the web.
- Common control radius: 6.
- Card and sheet radius: 10 to 12.
- Status chip radius: fully rounded only when the label is genuinely a status.
- Borders: one physical pixel where the renderer permits it.
- Minimum touch target: 44 by 44 pt.

Large soft pills, nested rounded cards and decorative blobs are outside this
system. A terminal user should be able to scan the alignment without decoding a
stack of containers.

### Elevation

Use no shadow for ordinary sections, rows or controls. Use a soft neutral shadow
only for a menu, sheet, phone mock-up or other object that physically overlaps
the current plane. Cobalt-tinted glow is not part of the system.

### Controls

- Primary: solid cobalt, one per view.
- Secondary: paper or transparent fill with a neutral border.
- Tertiary: text or icon only.
- Destructive: red text by default; solid red only at the final destructive
  confirmation.
- Focus: 2 px cobalt outline with a 2 px paper offset on the web.
- Disabled: neutral treatment plus reduced contrast, never opacity alone where
  the label becomes unreadable.

### Motion

Movement confirms an action or change of state. Controls use 120 to 160 ms
transitions. Sheets may use the platform transition. Avoid ambient gradients,
floating elements, looping status animation and motion that makes a working
Agent look faster than it is.

## Imagery and product presentation

- Show the actual Herden interface or a privacy-safe edit of a real capture.
- Generic Space names must look plausible: `landing-page`, `fix-auth`,
  `payments`.
- Device renders support the product story. They do not become the page's main
  decoration.
- AR glasses should show the real simulator composition inside the display
  area. The hardware render remains secondary to the iPhone and terminal story.
- Do not add luminous gradients, glass cards, fake analytics, abstract meshes or
  AI-generated interface chrome.
- On the compact landing page, keep the two phones and the smaller glasses in
  the opening view. The page should remain roughly one or two mobile screens.

## Logo system

The logo pass must follow the palette's restraint rather than recolour the old
mark mechanically.

Decision recorded on 13 September 2026: the symbol is fair game. The existing
Fold geometry is not protected. Preserve the product meaning and operational
constraints below, not the current silhouette. `Fold` may remain an internal
asset name during migration, but it does not constrain the design.

Final mark selected on 13 September 2026: **Live Tether LT 01**. The mark uses
two stable endpoints joined by one explicit angular channel. It represents the
same live terminal continuing between Host and device without drawing either
device literally. The approved 120-unit construction uses two 32-unit endpoints
and a 14-unit tether. The Space mark is the source and outgoing route; the Agent
mark is the incoming route and destination.

### Meaning

The Herden mark should communicate one of these ideas without becoming a
literal illustration:

- a Space holding an Agent;
- two clients meeting at one live terminal;
- motion continuing while the user steps away;
- a fold or passage between desktop and phone.

### Colour

The primary Live Tether mark is one colour:

| Appearance | Mark | Field |
| --- | --- | --- |
| Light | `#205EA6` | `#FFFCF0` |
| Dark | `#4385BE` | `#100F0F` |
| Monochrome light | `#100F0F` | transparent or paper |
| Monochrome dark | `#F2F0E5` | transparent or ink |

Rust must not permanently fill one half of the mark. That treatment makes a
warning colour look like half of Herden's identity and breaks the semantic
system. Rust may appear as a temporary notification dot outside the mark.

### Construction constraints

- Default to a single, recognisable silhouette.
- Work at 16, 20, 32, 64 and 1024 px.
- Survive one-colour printing and iOS tinted icons.
- Keep interior openings visible at 16 px.
- Avoid hairlines, gradients, shadows and small detached pieces.
- Build Agent and Space submarks from the same geometry as the full mark.
- Balance the shape optically inside a square. Mathematical centring is not
  sufficient.
- Pair with a plain `Herden` wordmark. Do not force the symbol into a custom
  letterform.

### Exploration record

The first pass compared Space and Agent, terminal passage, and continuity
families in cobalt on paper, cobalt on ink, monochrome, favicon size and an iOS
icon crop. Literal prompts and window frames looked like generic developer-tool
logos. Live Tether was selected from the continuity family because its two
endpoints and single channel remained clear without those clichés.

The refinement pass compared endpoint size, device-like proportion, channel
weight, direction and corner treatment. The approved family includes the
derived Agent and Space marks, monochrome reproduction, tinted iOS treatment
and 16 px rendering.

## Product ownership boundaries

### Native app

`HerdenBrand.swift` should own the semantic light/dark tokens. Views consume
roles such as `primary`, `attention` and `fault`, not colour-specific names such
as `vine` or `amber`.

Appearance-aware product, Agent and Space marks must be generated from the same
approved geometry and colours. App Icon Composer needs matching light, dark and
tinted treatments.

At compact list-row size, use the complete Live Tether beside each Space. The
derived Space endpoint is valid as a standalone taxonomy mark, but reads like a
cropped product logo when repeated beside labelled rows.

### Public site

The landing page uses the same tokens but retains its all-monospace voice. It
must stay compact and zero-client-JavaScript. Logo SVGs, favicon, OpenGraph card
and product screenshots are one release unit.

### Terminal

The brand palette belongs to application chrome. It does not replace the user's
terminal theme and must never be injected into a shared PTY at Agent launch.
Ghostty remains the renderer and the selected local daylight/nighttime terminal
pair remains client-owned, as specified by ADR 0023.

## Migration map

This table describes the intended semantic migration. It is not a reason to
blindly rename every reference.

| Current app role | Paper + Cobalt role | Note |
| --- | --- | --- |
| `background` | `canvas` | New paper and ink values |
| `elevated` | `surface` | Quiet grouped surface |
| `card` | `surfaceRaised` | Use less often than today |
| `ink` | `ink` | Keep semantic name |
| `muted` | `inkMuted` | Clarify text role |
| `subtle` | `inkSubtle` | Clarify text role |
| `vine` | `primary` | Cobalt replaces green identity |
| `vineLight` | `primaryStrong` or remove | Prefer state-specific use |
| `vineDark` | `primaryPressed` | Appearance-aware interaction state |
| `amber` | `attention` | Merge overlapping warm signals |
| `uploadOrange` | `attention` or `fault` | Decide from the actual state |
| `fault` | `fault` | Keep semantic name with new pair |
| `hairline` | `border` | Use explicit light/dark values |

## Rejected patterns

- Green as both brand and success.
- Orange or rust as a decorative second brand colour.
- A split cobalt/rust logo.
- White SaaS cards floating on cream.
- Purple-blue gradients, glow and frosted glass.
- Huge rounded panels with one sentence in each.
- Serif display type added only to imply taste.
- A separate visual language for the website and the iOS app.
- Recolouring the terminal to match application chrome.
- Enlarging the AR glasses until they compete with the phone.

## Acceptance checklist

Before the direction reaches production:

- [x] Light and dark app screens use the semantic token map.
- [x] Primary, attention, success and fault states are distinguishable without
      colour.
- [x] Normal text and controls meet WCAG AA in both appearances.
- [x] The approved logo passes 16 px, monochrome and iOS tinted-icon tests.
- [x] Full product, Agent and Space marks share one geometry system.
- [x] Website logo, favicon, OpenGraph card and app assets match.
- [x] Landing page still fits the compact one-to-two-screen brief on mobile.
- [x] Real iOS captures replace any colour-only mock interface.
- [x] AR glasses remain smaller than the primary phone and contain the real
      simulator view.
- [x] No client colour is sent to the Host or shared PTY.
- [ ] Light and dark screenshots are reviewed on physical iPhones. Manual
      appearance review on physical displays remains intentionally separate
      from simulator and automated release checks.
