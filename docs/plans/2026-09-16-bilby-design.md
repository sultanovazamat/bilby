# Bilby — design

Date: 2026-09-16

## Problem

People who work in a second language lose the thread in meetings. macOS 26
ships live translation, but only inside Messages, FaceTime and Phone. Zoom,
Meet, Teams, YouTube and recorded lectures get nothing.

## What it is

A translucent caption bar pinned to the bottom of the screen. English audio
from any app goes in; the user's own language appears under it, live. Clicking
a phrase asks the on-device model to explain it.

## Decisions and why

**Output audio only, never the microphone.** A Core Audio process tap
(`AudioHardwareCreateProcessTap`, macOS 14.4+) gives Zoom's decoded stream —
clean, digital, pre-speaker. A microphone would add room noise and, on
speakers, transcribe every sentence twice. Tapping output also yields
*everyone except the user*, which is exactly the job. And never requesting
microphone permission is worth more than the feature it would buy.

**Two tiers at different speeds.** The source line updates word by word,
sub-second. The translated line lands at clause boundaries, 1–3 s later, and is
never rewritten. The asymmetry is what makes the bar feel live while the
translation catches up. Rewriting visible captions is what makes cheap
captioning apps feel broken.

**The LLM stays out of the hot path.** Explanation runs only on click.

**Sequential translation.** Concurrent calls would finish out of order and
force lines to be reshuffled. `Transcript` forbids rewriting, so translation
is sequential by design, not by simplification.

**AppKit owns the window, SwiftUI draws inside it.** The panel needs
`.nonactivatingPanel`, `level = .screenSaver`,
`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
`ignoresMouseEvents`, and `sharingType = .none` so it is invisible during
screen sharing. SwiftUI cannot express any of that.

## Stack

Swift 6, zero third-party dependencies. `SpeechAnalyzer`/`SpeechTranscriber`,
`Translation`, `FoundationModels`, Core Audio process taps. macOS 26 and
Apple silicon required; without Apple Intelligence, captions and translation
still work and only "explain" disappears.

## Risks

1. **Latency.** Unmeasured. If end-to-end exceeds ~2.5 s this is a transcript
   viewer, not a caption bar. M1 settles it.
2. **`TranslationSession` is bound to SwiftUI view lifecycle.** The translation
   engine wants to be a plain service. If it cannot detach, fall back to a
   hidden SwiftUI host or a local model.
3. **Language coverage is unpublished.** `SpeechTranscriber.supportedLocales`
   must be read at runtime; a `swift` script could not do it, so M1 needs a
   real app bundle.
4. **macOS 26 + Apple silicon only.** Judges on Sequoia or Intel cannot run it.

## Milestones

- **M0** repo, core, tests, purity gate — done
- **M1** spike: measure latency, settle risks 2 and 3 — blocking
- **M2** CLI harness over fixtures
- **M3** real audio tap → transcription → translation
- **M4** the panel
- **M5** explain, onboarding, polish

## Acceptance criteria

1. Spoken word to translated line under 2.5 s on a recorded call.
2. A translated line is never rewritten.
3. Panel floats over full-screen apps, passes clicks through, invisible in
   screen sharing. *(Reversed on 2026-10-01 by the owner: macOS hides a window
   from screen sharing only by hiding it from screenshots and recordings too,
   and a captions app has to be recordable. The captions now show in all
   three.)*
4. Microphone permission never requested.
5. `BilbyCore` imports no platform framework (enforced by script).
6. Without Apple Intelligence, only "explain" degrades.
7. Zero third-party dependencies.
