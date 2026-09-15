# Harness pixel marks

Space and Agent rows show a 42-point pixel-letter tile in place of the repeated
Herden mark. The adjacent text remains the source of truth for the occupant.
The tile is a quick visual cue, not a third-party logo or a claim of affiliation.

Herden draws its own three-by-five pixel alphabet. Pi is **P**, Claude Code is
**C**, and Codex is **Cx** to distinguish it from Claude; the other supported
Agent kinds use their first letter. The tile colours approximate each product's
recognizable public accent. Products with monochrome presentation use dark ink.
Pi and Codex use neutral ink, matching their compact monochrome presentation.
Brand colours are cues, not exact or permanent vendor identity standards; a
vendor can change them without changing Herden's Agent wire kind.

The Host's `detect::Agent::ALL` is the source list: 24 kinds, including Letta.
The iOS `SupportedAgentKind` catalog and mark palette must cover each one. An
unknown kind gets a cobalt `?` tile and its literal Host-provided name.

Plain terminals get an ink `>` tile. When `pane.process_info` positively names
the foreground shell as zsh, Bash or fish, the tile becomes **Z**, **B** or **F**
and the row says which shell it saw. When the method is absent, the shell is
busy with another foreground process, or the report is ambiguous, the generic
Terminal mark stays. The UI never infers a shell from a project name or title.

No vendor logo assets are bundled. This avoids modified or lookalike versions
of marks whose owners prohibit them, and keeps Herden's own Live Tether as the
app/site identity rather than a Space occupant mark. Public examples of the
relevant policies and colour sources are [OpenAI's brand guidelines](https://openai.com/brand/),
[Google's brand guidance](https://about.google/brand-resource-center/guidance/),
[GitHub Copilot's palette](https://brand.github.com/brand-identity/copilot),
[Pi's press-kit badge](https://pi.dev/press-kit),
and [Cursor's brand page](https://cursor.com/brand).
