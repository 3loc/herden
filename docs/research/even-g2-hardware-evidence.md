# Even G2 physical-device evidence

Status: **private package path verified; extended physical validation pending**.

No result is recorded here until it is observed on a paired Even Realities G2
and an installed iPhone Even app. Simulator and CLI results do not satisfy this
gate.

| Requirement | Evidence required | Result |
| --- | --- | --- |
| Tailnet HTTP, SSE, authenticated read-only request | iOS/Even/SDK/firmware versions, exact host URL, steps and observation | Pending |
| Explicit LAN HTTP, SSE, authenticated request | Same, including ATS, local-network and WebView policy | Pending |
| Whitelist and install semantics | Omitted/empty/wildcard/IP/port/exact-origin behaviour; package/sideload requirements | Exact HTTPS origin, `.ehpk` upload, beta assignment, install and launch verified 2026-09-21 with SDK 0.0.15; other whitelist forms remain untested |
| Locked phone lifecycle | At least 30 minutes with known Agent transitions, near the end of trial | Pending |
| Wear, BLE and network recovery | Disconnect/reconnect and Wi-Fi/cellular observations | Pending |
| Glance/wake | Documented SDK/firmware call and physical observation | Pending |
| Dictated write path (`POST /command` `send_text`) | From the packaged Even app on a worn G2: the spoken phrase's transcript, the exact request body, and a `pane.read` showing the text sitting unexecuted in the Agent's prompt with `submit: false` | Pending — Host side verified over Tailnet HTTP only |
| Idle battery | One-hour baseline comparison, brightness, network, wear state and update count | Pending |

The private beta proves that a reusable `.ehpk` can use its exact HTTPS origin.
Until the other required rows have observed evidence, do not claim direct
Tailnet/LAN support for packaged apps, reliable background availability, or
repeatable wake and recovery behaviour.

## Private beta observation — 2026-09-21

- Built with Even Hub SDK 0.0.15 and a generated manifest containing one exact
  HTTPS origin; no Host credential or maintainer hostname was committed.
- Uploaded to Even Hub, assigned to the designated beta tester, installed, and
  opened on a paired G2. A prior test invitation had expired; changing the
  uploaded version to Beta restored tester access.
- The installed app received four Host SSE streams and sent audio to the
  transcription route through the same gateway origin. The gateway injects
  protected per-Host credentials and does not persist audio.
- The wearer confirmed that the installed beta works. The full 30-minute
  locked-phone, recovery, dictated-write capture, repeatable wake, and battery
  sequence was not recorded and remains pending.

## QR-sideload observations — 2026-09-19

These are physical G2 observations from an Even Hub QR development sideload,
not evidence for the packaged-app rows above:

- The phone loaded a private-LAN Vite development URL and rendered the
  four-tile HUD on worn G2 hardware. Its development proxy streamed live SSE
  snapshots from three private Hosts; bearer credentials remained in the proxy
  process.
- Scroll and long-press events arrived. Click events did not arrive despite an
  event-capturing text surface and checks of every SDK event envelope.
- Continuous microphone capture delivered 1,600-byte PCM frames at about 20
  frames per second. WAV uploads transcribed spoken `open` commands through
  Parakeet; the 16 kHz mono s16le interpretation remains inferred rather than
  declared by the SDK.
- The original fixed 2% RMS endpoint threshold failed in changing background
  noise: saved 9.2 s and 10.55 s clips combined separate phrases, and two clips
  hit the 15 s cap. Replaying all 29 saved hardware clips through the adaptive
  endpoint split the 10.55 s capture into separate segments which Parakeet
  transcribed as `Open three.` and `Open four.` Physical confirmation of the
  new endpoint on a fresh spoken command remains pending.
- An earlier apparent head-up tilt wake was attributed to Y; the marked
  20 September directional capture disproved that axis assignment. Looking up
  drove X from near 0 to about +0.35 while Y moved only slightly negative;
  right and left level turns kept X near neutral; looking down drove X to
  about -0.8. The long stable X≈+0.037 portion of the down interval was the
  glasses resting on a table, not a worn head pose. The corrected detector
  uses positive X movement, relative to the current resting pose. The HUD
  still owns the display while foreground and has no proven
  glasses-only exit path; force-quitting the phone app releases it.
- The four-image-tile text renderer overloaded the live display path. In one
  lit session telemetry recorded 685 requested frames, 76 four-tile writes,
  15 timeouts, 10 page rebuilds and a tile-3 `sendFailed`; the wearer observed
  repeated redraws followed by one eye going dark. Device status remained
  connected, worn, and fully charged, isolating the failure to rendering rather
  than a BLE disconnect.
- The replacement native-text build (`native-text-1`) produced one successful
  text update on tilt wake and one successful blank update at idle, with no
  render errors or runtime page rebuild. Unknown ambient transcripts did not
  repaint or extend the idle interval. The complete `open <n>` / `go back`
  physical acceptance sequence remains pending.
- `isWearing` is not a safe lifecycle signal: a live worn session reported
  `false`, and treating it as authoritative blocked tilt wake and disconnected
  the Host. Native-text build `native-text-2` keeps it as telemetry only.
- A dark session now re-bases and re-arms tilt from the pose at sleep. Lowering
  the head while dark immediately establishes rest, so the next upward motion
  cannot inherit the previous session's disarmed detector state
  (`native-text-3`). The fixed native font has no size control; detail chrome
  was collapsed from three rows to one, increasing visible output from 7 to 9
  rows without returning to bitmap image updates.
- A deliberate second wake in the `native-text-3` trace reached a +0.138 pitch
  delta while ordinary dark-state motion peaked around +0.09, so it narrowly
  missed the old +0.150 trigger. `native-text-4` sets the measured wake
  threshold to +0.120.
- The `topaz-1` experiment restored classic Topaz A500 at 8×16 pixels, but it
  supported printable ASCII only and returned to four image transfers per
  frame. The wearer then observed another one-eye display failure despite
  successful SDK callbacks. That renderer is rejected; `native-text-5` returns
  to one zero-padding firmware text container and never calls
  `updateImageRawData`.
- On 20 September the wearer reported that the dark display relit without a
  deliberate head-up tilt. Code review found that any Hub event, including a
  foreground event or touch, woke a dark lens. An initial attempt also froze
  the sleeping baseline and required two high IMU samples, but the wearer
  reported that tilt no longer woke the display. That unverified tightening
  was removed. The next trial still woke and slept unpredictably. The ensuing
  absolute transition gate was also wrong: the `voice-resilience-3` trace
  showed dark-state Y resting around +0.03 for seven minutes, while the gate
  demanded Y <= -0.05 before another wake could be detected. The detector now
  anchors to the pose at sleep, follows long-term posture drift while dark,
  and wakes on a measured +0.12 relative rise. The Hub's foreground exit
  event is a contextual-menu overlay closing, not app termination; it no
  longer darkens the lens or stops capture. Both corrections are backed by
  regression tests, but still need physical confirmation. Vite's log also
  showed repeated phone-page reloads as development source changed; QR
  hardware sessions now disable hot reload.
- Code review of the installed Even Hub SDK 0.0.15 declarations found that
  startup-page result `1` means an invalid container, not an existing page.
  The HUD previously rebuilt the page on `1`; it now fails visibly on the
  phone instead. This removes an unjustified rebuild path, but does not by
  itself prove the one-eye blackout is resolved on hardware.
