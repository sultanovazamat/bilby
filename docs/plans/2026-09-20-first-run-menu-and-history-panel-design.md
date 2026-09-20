# First run, menu, and the history panel — design

Date: 2026-09-20. Follows the UX review of the app at commit 2302f23.

## Problem

Walking the app as a non-technical user found three classes of defect.

1. **It does not survive another Mac.** The SwiftPM resource accessor looks
   for `Bilby_BilbyUI.bundle` at the app's top level or at this repo's
   absolute `.build` path. `make-app.sh` copies it to neither place, so the
   installed app works here by accident and dies with
   `Fatal error: could not load resource bundle` on the first onboarding page
   anywhere else. Verified by running it with the `.build` folder denied.
   `release.sh` also packages a stale `.build/Bilby.app`, and SwiftUI's
   `Image(name, bundle:)` draws nothing for the loose PNG screenshots, so the
   two "where to click" pages show an empty box.
2. **The first run has dead ends.** The last page's button is disabled until
   a caption arrives, which on a fresh Mac means a silent 580 MB download and a
   compile with no progress, and closing the window does not mark setup done,
   so onboarding returns at every launch. The permission page sends people to
   a System Settings pane where Bilby is not yet listed. The language defaults
   to Russian for everyone. Adding a language from the menu replays the whole
   flow.
3. **Daily use gives no feedback.** The icon never changes, "Pause" loses the
   app name, nothing shows the current app or language, status text is
   developer language, and the bar is invisible for the first 14–50 s of a
   session. The two caption lines are usually two different sentences with
   nothing saying so. And a slow reader cannot go back: once a translation
   scrolls away it is gone.

## Decisions

**Resources.** BilbyUI stops using `Bundle.module`. A resolver looks in
`Bundle.main.resourceURL` (Contents/Resources in the app), then beside the
executable (the preview tool), and returns nil rather than crashing. Images
load as `NSImage` via `image(forResource:)`, which draws. `release.sh` stages
the app that `make-app.sh` just built, in release configuration. A new
`Scripts/check-app-portable.sh` launches the built app with the repo's
`.build` denied and fails if it dies: the crash can never return unnoticed.

**Setup is done when the last page is reached.** "Start using Bilby" is
always enabled. Closing the window from the last page is finishing.

**Speech recognition is visible.** The recogniser reports readiness:
`downloading(fraction)`, `preparing`, `ready`, `failed(message)`. Warm-up
starts when the user reaches the language page. The last page shows the phase
and a percentage, and offers Retry on failure. In daily use the bar shows a
dim status line — "Getting ready…", then "Listening to Google Chrome…" — until
the first words, and the menu never reports "No audio from that app" while
loading. When the stream ends for any reason the listening flag resets.

**Language defaults from the system.** The first preferred language that
Apple can translate into, excluding English. If there is none, the picker is
unselected and the button waits for a choice.

**Add Language opens the language page.** `SetupModel` takes a starting step.
Started at `.language`, finishing the download closes the window; welcome,
permission and try-it are not replayed.

**Permission with nothing playing is not a dead end.** If no app has played
audio, the button reads "Continue anyway" and the page says Bilby will ask
the first time captions start.

**Status text is for people.** Diagnostics keep their counters; a pure
mapping turns them into sentences: "No sound from Google Chrome yet. Is it
muted?", "Listening — no speech heard yet", "Bilby isn't allowed to hear
other apps." with a "Fix Permission…" item that opens the pane. Raw Core Audio
codes stay in the log.

**The menu shows state and nothing redundant.**

```
Start Captions for Google Chrome   ⌘P     (Stop Captions for … while running)
──────
Listen To                           ▸     only when two or more apps can be heard; checkmark on the current one
Language                            ▸     installed languages with a checkmark, then Add Language…
✓ Show Sentence History                   checkable; switches bar ↔ panel
──────
Fix Permission…                           only when the tap was refused
Quit Bilby                          ⌘Q
```

A pure `MenuState` struct computes titles and visibility from the app's
state so this is tested with strings. The menu bar icon gains a small dot
while captions run. "Open Bilby at login" is a checkbox on the last setup
page, via `SMAppService`.

**The bar shows one sentence.** Top line and bottom line always belong to
the same sentence. At a boundary the pair switches together: the bar holds
the finished sentence and its settled translation until the next sentence
has a draft, then both lines move on. The cost is a live line that lags by up
to a second at sentence starts; the gain is that the reader is never shown a
translation of something other than the line above it.

**The history panel.** A second `NSPanel`, non-activating, `.floating` level
with `.fullScreenAuxiliary`, `sharingType = .none`, movable and resizable,
docked to the right edge at about 380 pt wide and the visible screen height,
frame remembered in UserDefaults. It accepts scrolling and never takes
keyboard focus. Rows are sentences: source small and secondary above,
translation larger and primary below, newest at the bottom, the sentence
being spoken as a dim live row underneath. It auto-scrolls until the user
scrolls up, then shows a "Latest" button. History is the session's lines,
capped at 500. Bar and panel are modes, not layers: showing the panel hides
the bar. The mode persists.

## Architecture

New or changed pieces, all behind the existing seams:

- `BilbyUI/UIResources.swift` — bundle resolver and `screenshot(named:)`.
- `BilbyCore/Models.swift` — `Readiness`, `AudioAccess` and
  `LoginItemOutcome`: plain enums, because both `BilbySources` (which
  produces them) and `BilbyUI` (which shows them) import the core and
  neither imports the other.
- `BilbySources/AudioTranscribing.swift` — `warmUp(progress:)`;
  `UnifiedTranscriber` forwards FluidAudio's progress handler.
- `BilbyUI/CaptionModel.swift` — keeps `lines` for the session (capped),
  adds `status` text and the `pair` the bar shows.
- `BilbyUI/HistoryPanel.swift`, `HistoryView.swift` — the side mode.
- `BilbyUI/MenuState.swift` — pure menu model.
- `BilbyUI/StatusText.swift` — diagnostics to sentences.
- `BilbyUI/SetupModel.swift` — starting step, readiness, done-on-arrival,
  login item, default language injection.
- `BilbyApp/BilbyApp.swift` — wires the above; owns the mode switch.
- `Scripts/` — `make-app.sh` config flag, `release.sh` staging,
  `check-app-portable.sh`.

Data flow is unchanged: audio → utterances → `CaptionSession` events →
`CaptionModel`. The bar and the panel are two views of the same model; the
delegate orders one or the other front.

## Error handling

- Missing resource bundle: the page falls back to the drawn illustration.
- Model download fails or offline: readiness `.failed(message)`; setup shows
  Retry; the menu shows the message; listening resets.
- Permission refused mid-session: `Diagnostics.failure` carries the tap
  status; the menu shows "Bilby isn't allowed to hear other apps" and
  "Fix Permission…".
- Language download cancelled or failed: unchanged, already handled.

## Testing

String-level tests, no hardware, in `Tests/BilbyUITests`:

- `SetupModelTests` — existing tests corrected to "confirm, don't skip"; the
  hang replaced by a test of the arrival state; new: starting at `.language`,
  done on reaching `.tryIt`, readiness gating the status text, default
  language from an injected preferred list, empty preferred list leaves the
  picker unselected, login-item toggle recorded.
- `CaptionModelTests` — history cap, pair coherence at a sentence boundary,
  status line while not ready.
- `MenuStateTests` — titles and visibility for idle, listening, one app, many
  apps, permission failure.
- `StatusTextTests` — every diagnostics case to its sentence.
- `Scripts/check-app-portable.sh` — the built app launches with `.build`
  unreadable.
- `swift run BilbyPreview --output` renders every setup scene, both caption
  modes, and the menu bar icon in both states.

## Out of scope

Gatekeeper needs a Developer ID and notarisation. Text size, bar position and
hiding the source line are follow-ups. The panel appears on the main display
only, like the bar.

---

# Revision, 2026-09-20: the windows carry their own controls

The mode switch was a checkable item in the menu bar. That is the wrong place
for it: switching between the bar and the column is something you do *to the
window in front of you*, and every other window on the machine offers that on
the window itself. It also meant the menu carried a fifth item that was not
about starting, stopping, or choosing.

## Decisions

**A control strip, on both surfaces.** A 28 pt band along the top of each
caption window, tinted apart from the text and separated by a hairline,
holding the three familiar buttons at the left: red closes, yellow collapses
to the bar, green expands to the column. The one that would do nothing is
greyed rather than hidden, as Finder greys zoom, so the row never changes
shape. Glyphs appear on hover, over the whole strip at once. Text lives below
the band and cannot reach it: a caption that grew into the buttons would be
both unreadable and unclickable.

**Red stops captioning.** Closing the window ends the session, the way closing
a document window ends editing it, rather than hiding a session that goes on
running unseen. The menu's Stop does the same thing.

**The bar is no longer click-through.** A control drawn on a window that
ignores the mouse cannot be pressed, and per-region pass-through across
applications is not something AppKit offers. What replaces clicking through
it is moving it: the bar is draggable anywhere on its surface and remembers
where it was left. It also grows upward from its bottom edge now instead of
re-centring, so a second line pushes the first one up rather than dragging the
whole bar down over whatever it was placed to avoid.

**The column follows the live sentence.** It scrolls with new text until the
reader scrolls up, which is a statement that they are reading something.
A round arrow then fades in at the bottom right — where a scroll view's own
thumb ends — and one click returns to the live sentence and resumes
following. Scrolling back down by hand resumes it too. The old "Latest" pill
at the bottom centre is gone. The rule is a three-line value type,
`LiveFollow`, so it is tested rather than watched.

**The column is borderless too.** It keeps `.resizable` so how much history
fits stays the reader's business, but drops the system title bar: with a strip
of its own, a second row of buttons above it would be absurd, and a
transparent title bar swallows clicks in the region where our own buttons sit.

**The menu loses "Show Sentence History".** Four items in the ordinary case.

## Consequences

- Both windows take mouse events, so both need a hosting view that accepts the
  first click; otherwise AppKit spends it making a window key that must never
  become key.
- Text selection in the column is gone for now. It was the one interaction
  that could pull focus, and copying a transcript deserves to be a deliberate
  action rather than a side effect of dragging.
