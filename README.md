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
SystemAudioTap    (CoreAudio) ─┐
AudioTranscribing (FluidAudio)─┼──▶  CaptionSession          ──▶   CaptionPanel
Translating       (Translation)┘       └── CaptionEngine            MenuBarExtra
                                             ├── ClauseBuffer
                                             └── Transcript
```

Each edge the core depends on is a protocol with a real implementation and a
fake: `Translating` in `Ports.swift`, `AudioTranscribing` in BilbySources.
Swapping translation for a local model is a new `Translating`. The core does
not change.

`ClauseBuffer` is where the product's feel lives: it decides when speech is
complete enough to translate. Cut too early and the grammar is wrong; cut too
late and captions lag.

## Build

```
./Scripts/check.sh              # tests, purity, release build, portable app — run this
./Scripts/release.sh            # Bilby.dmg: release build, checked, ad-hoc signed
swift run BilbyPreview --output .build/previews   # every setup scene, both caption modes
```

`check.sh` builds in release on purpose: strict concurrency finds races under
whole-module optimisation that the debug build accepts, and one sat in the
tree unnoticed because nothing ran it between disk images.

`release.sh` lays the install window out with `dmgbuild`, which it installs on
first use into `.build/dmgtools` — so that one run needs `python3` and a
network. Later runs do not. `Scripts/dmg-settings.py` is what the window looks
like; `Scripts/check-dmg.sh` reads the finished image back and fails if it
does not match.

## Status

Live captions and translation work end to end (M1 findings in
`docs/plans/2026-09-16-m1-spike-findings.md`; engine choice in
`docs/plans/2026-09-16-engine-choice.md`). The first run, the menu and the
history panel follow `docs/plans/2026-09-20-first-run-menu-and-history-panel-design.md`.
Not done: "explain", a signed and notarised build, text size and bar position.
