# Herden App Store screenshot exports

The generator preserves the exact application UI from the committed iPhone
captures and adds deterministic marketing copy over a generated background.
Run `./compose_mockups.py` on macOS to create the exports below. The
pre-rename exports were removed and must not be reused.

## Exports

- iphone-6.9/01-type-directly-stay-in-flow.png
  - Source: docs/images/composer-iphone.png
  - Copy: “Type Directly. Stay in Flow.”
- iphone-6.9/02-control-without-leaving-the-flow.png
  - Source: docs/images/agent-iphone.png
  - Copy: “Control Without Leaving the Flow”
- iphone-6.9/03-your-shell-within-reach.png
  - Source: docs/images/terminal-iphone.png
  - Copy: “Your Shell. Within Reach.”
- iphone-6.9/04-your-agents-at-a-glance.png
  - Source: docs/images/live-activity-iphone.png
  - Copy: “Your Agents. At a Glance.”

All files are opaque 1320×2868 PNGs for the iPhone 6.9-inch App Store slot.

## Provenance

The background was generated with OpenAI image generation as an abstract,
text-free dark terminal texture. All UI, headlines, subheads, borders, masks,
and sizing are composed locally by compose_mockups.py; the source screenshots
are never redrawn by a generative model.
