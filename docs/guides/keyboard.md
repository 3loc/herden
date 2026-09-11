# A keyboard for the work in front of you

Herden shows the Agent's real terminal. What you type or dictate goes to that
prompt. The phone is a way to continue the work on your Host, with the controls
you need within thumb reach.

## Write, correct, then send

Tap the prompt to show the iPhone keyboard. Type your message, or choose a
**Dictation Language** from **More** and tap **Dictate text**. Dictation transcribes
on the phone and never presses Return. Tap Stop when finished.

To correct a character or word, tap within the prompt and drag left or right
to move its cursor. Touch editing stops dictation first, so a later recognition
update cannot revise text at the new cursor position. Use Backspace to remove
the character before the cursor, then type the replacement. Holding the iOS
space bar also provides its familiar keyboard trackpad.

For example, to change “open the blue file” to “open the green file”, move the
cursor just after “blue” with the left/right arrows, press Backspace four times,
and type “green”. The rest
of the sentence stays in place. Press Return only when you are ready to submit.

Autocorrection, smart punctuation and automatic capitalisation are disabled
because terminal input must preserve what you intend. Dictation currently
normalises its transcript to lowercase. The language menu is deliberately
limited to Traditional Chinese (Taiwan), Simplified Chinese, Swedish,
Portuguese (Portugal), English (US), German and French, using available
on-device models.

## Everyday controls

The toolbar stays above Apple's keyboard. **Left** and **Right** move the
cursor; hold either arrow to repeat. **Attach** opens Documents or Photos,
and **Paste** inserts clipboard text. The keyboard button shows or hides the
system keyboard. **More** holds Escape, Tab, interrupt (Ctrl-C), Ctrl-B, Up,
Down, Return and dictation language.

Existing Agents may use Vim editing. If an Agent is in normal mode, choose
**More → Insert text (Vim)** before typing. Herden passes that explicit action
to the Agent; scrolling and cursor movement do not change editing modes.

## Record an audio attachment

**Dictate text** uses Apple's on-device speech recognition and inserts text.
**Record audio** keeps your voice as a compressed M4A recording instead.

Tap **Stop recording**, listen with **Play**, then choose **Attach audio** or
**Discard**. Recordings stop after ten minutes or when interrupted/backgrounded;
they never resume recording automatically. Cancelling the sheet discards the
local recording. An upload that fails can be retried through the attachment
status bar.

Audio uses the same SSH file upload as Documents. Herden inserts its Host path
without pressing Return. The Agent needs audio support to consume the file.
Completed Host files remain there; Herden removes its temporary local copy.

## Move between work

Tap a Space or Agent in the picker to enter its terminal. Swipe **right across
terminal output** to return to the picker. Swipe **left across the picker** to
reopen the last Agent or Space. The bottom strip switches directly to another Agent.

A horizontal drag beginning **inside the prompt** always belongs to cursor
editing. A vertical drag scrolls terminal output. The explicit back control
remains available if you prefer tapping or use VoiceOver. Leaving a terminal
keeps its remote process running.
