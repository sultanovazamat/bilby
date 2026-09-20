# Bilby

Live captions and translation for any audio playing on your Mac.
Everything runs on device. The microphone is never used.

## Why it exists

macOS 26 ships live translation only inside Messages, FaceTime and Phone.
Every meeting actually happens in Zoom, Meet or Teams. Bilby is the caption
bar for those.

## Architecture

Apple's frameworks live at the edges. The middle is pure Swift, so the whole
product can be tested with strings — no audio, no network, no Apple Intelligence.

```
edges (untestable)              core (pure, covered by tests)        ui
──────────────────              ─────────────────────────────        ──────────────
AudioSource    (CoreAudio)  ─┐
Transcribing   (Speech)     ─┼──▶  CaptionSession            ──▶   CaptionPanel
Translating    (Translation)─┤       └── CaptionEngine              MenuBarExtra
Explaining     (FoundationM)─┘             ├── ClauseBuffer
                                           └── Transcript
```

Each edge is a protocol in `Ports.swift` with a real implementation and a fake.
Adding microphone capture is a new `AudioSource`; swapping translation for a
local model is a new `Translating`. The core does not change.

`ClauseBuffer` is where the product's feel lives: it decides when speech is
complete enough to translate. Cut too early and the grammar is wrong; cut too
late and captions lag.

## Build

```
swift test                      # 76 tests, no hardware required
./Scripts/check-core-purity.sh  # core must not import platform frameworks
./Scripts/make-app.sh           # ~/Applications/Bilby.app, debug build
./Scripts/check-app-portable.sh # the app must run with this checkout unreadable
./Scripts/release.sh            # Bilby.dmg: release build, checked, ad-hoc signed
swift run BilbyPreview --output .build/previews   # every setup scene, both caption modes
```

## Status

Live captions and translation work end to end (M1 findings in
`docs/plans/2026-09-16-m1-spike-findings.md`; engine choice in
`docs/plans/2026-09-16-engine-choice.md`). The first run, the menu and the
history panel follow `docs/plans/2026-09-20-first-run-menu-and-history-panel-design.md`.
Not done: "explain", a signed and notarised build, text size and bar position.
