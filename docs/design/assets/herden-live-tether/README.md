# Herden Live Tether assets

Selected logo geometry for the Paper + Cobalt visual system.

## Construction

The product mark uses a 120 by 120 coordinate space:

- first endpoint: `32 × 32` at `(16, 22)`, radius `2`;
- second endpoint: `32 × 32` at `(72, 66)`, radius `2`;
- tether: `M44 38 h20 v44 h12`, width `14`, square caps and mitre joins.

The two endpoints remain visibly distinct. The tether overlaps each endpoint so
the mark is mechanically continuous without looking like three equal blocks.

The Space mark is the first endpoint and outgoing half of the tether. The Agent
mark is the incoming half and second endpoint. They recombine exactly into the
product mark.

## Colour

| Appearance | Mark | Field |
| --- | --- | --- |
| Light | `#205EA6` | `#FFFCF0` |
| Dark | `#4385BE` | `#100F0F` |
| Monochrome | `#100F0F` | Transparent |
| Inverse | `#F2F0E5` | Transparent |

Rust is never part of the permanent mark.

## Files

- `herden-mark-*.svg`: transparent product marks.
- `herden-space-*.svg`: transparent Space marks.
- `herden-agent-*.svg`: transparent Agent marks.
- `herden-app-icon-*.svg`: full-bleed icon masters for platform masking.
- `herden-favicon-*.svg`: rounded browser/bookmark tiles.

The current app and website assets remain unchanged until the complete Paper +
Cobalt palette rollout. When integrating, update the iOS asset catalogue, Icon
Composer source, website SVGs, favicons, OpenGraph card and README artwork as
one change.
