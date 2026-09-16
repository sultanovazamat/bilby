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
swift test                     # 20 tests, no hardware required
./Scripts/check-core-purity.sh # core must not import platform frameworks
```

## Status

M0 complete: core, tests, purity gate.
M1 in progress — see `docs/plans/2026-09-16-m1-spike-findings.md`.
Settled: language coverage (9 source, 22 target), `TranslationSession` works
outside SwiftUI, no app bundle needed. Open: end-to-end latency.
