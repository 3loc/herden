# A keyboard for the work in front of you

Herden shows the Agent's real terminal. What you type or dictate goes to that
prompt. The phone is a way to continue the work on your Host, with the controls
you need within thumb reach.

## Write, correct, then send

Tap the prompt to show the iPhone keyboard. Type your message, or choose a
language from the terminal menu and tap the microphone. Dictation transcribes
on the phone and never presses Return. Tap Stop when finished.

To correct a character or word, tap within the prompt and drag left or right
to move its cursor. Touch editing stops dictation first, so a later recognition
update cannot revise text at the new cursor position. Use Backspace to remove
the character before the cursor, then type the replacement. Holding the iOS
space bar also provides its familiar keyboard trackpad.

For example, to change “open the blue file” to “open the green file”, move the
cursor just after “blue”, press Backspace four times, and type “green”. The rest
of the sentence stays in place. Press Return only when you are ready to submit.

Autocorrection, smart punctuation and automatic capitalisation are disabled
because terminal input must preserve what you intend. Dictation currently
normalises its transcript to lowercase. The language menu is deliberately
limited to Traditional Chinese (Taiwan), Simplified Chinese, Swedish,
Portuguese (Portugal), and English (US), using available on-device models.

## Vi controls

Herden supplies native vi settings when starting or restoring Claude and Codex.
This is a setting in each Agent's prompt editor. It does not install Vim or
change your shell's keyboard mode.

- **i:** enter insert mode to type or dictate.
- **Esc:** return to normal mode for vi commands.
- **h / l:** move left / right in normal mode.
- **j / k:** movement defined by the Agent's editor, often between prompt lines.
- **a:** enter insert mode after the cursor.
- **Ctrl-C:** interrupt; the Agent may ask you to press again before exiting.
- **Return:** submit or confirm the current prompt.

Native cursor keys sent by touch editing work in both normal and insert modes;
touch movement does not silently change modes. Press **i** before entering text
if the Agent is showing normal mode. The other vi keys are passed through to
the Agent, whose supported commands may differ from a full Vim editor.

Existing Agents retain their current mode until restarted or changed with
their own settings. When launching manually in a shell, use:

```sh
claude --settings '{"editorMode":"vim"}'
codex -c tui.vim_mode_default=true
```

To make the preference permanent outside Herden, merge `"editorMode": "vim"`
into your existing `~/.claude/settings.json`, and `vim_mode_default = true` into
the `[tui]` table of `~/.codex/config.toml`. Preserve the other settings; do not
replace the files. See [Claude's editor configuration](https://code.claude.com/docs/en/terminal-config)
and [Codex's configuration reference](https://developers.openai.com/codex/config-reference/).
These settings require Agent versions that support them.

## Move between work

Tap a Space or Agent in the picker to enter its terminal. Swipe **right across
terminal output** to return to the picker. Swipe **left across the picker** to
reopen the last Agent or Space. The bottom strip switches directly to another Agent.

A horizontal drag beginning **inside the prompt** always belongs to cursor
editing. A vertical drag scrolls terminal output. The explicit back control
remains available if you prefer tapping or use VoiceOver. Leaving a terminal
keeps its remote process running.
