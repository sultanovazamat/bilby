# M1 spike — findings

Date: 2026-09-16. Machine: M3 Pro, macOS 26.5.2.
Measured, not assumed. Source: `Spike/Sources/probe/Probe.swift`.

## 1. Transcription is the narrow end

`SpeechTranscriber.supportedLocales` — **30 locales, 9 languages**:

```
de (AT CH DE)   en (AU CA GB IE IN NZ SG US ZA)   es (CL ES MX US)
fr (BE CA CH FR)   it (CH IT)   ja   ko   pt (BR PT)   yue   zh (CN HK TW)
```

**No Russian, Ukrainian, Polish, Turkish, Arabic or Hindi.**

`installedLocales` — **9, all English variants.** English needs no download.

## 2. Translation is the wide end

`LanguageAvailability.supportedLanguages` — **38 locales, 22 languages**:

```
ar da de en es fr hi id it ja ko nb nl pl pt ru sv th tr uk vi zh
```

`status(en → ru)` = `supported`.

## 3. The product's shape follows from this

Bilby translates **from one of 9 languages into one of 22**. 198 pairs.

- English audio → Russian captions: **works.**
- Russian audio → English captions: **impossible.** There is no Russian speech model.

This is the intended use anyway — you sit in an English meeting and read your
own language. But it rules out an in-person mode for Russian, Polish, Turkish
or Arabic speakers, and that door is closed until Apple ships those models.

**And it sharpens the opportunity.** Apple ships the capability for 198 pairs
and the product for none of them outside Messages, FaceTime and Phone.

## 4. `TranslationSession` works outside SwiftUI — with one catch

`TranslationSession(installedSource:target:)` is a public initializer, compiles
and runs in a plain executable. Calling `translate(_:)` returned a semantic
error, not a framework complaint:

```
TranslationError(cause: .notInstalled, ...)
```

So: **translating needs no view. Downloading the language pack does** — that
path is the SwiftUI `.translationTask` modifier with system-presented UI.

**Consequence:** a hidden SwiftUI host during onboarding triggers the download
once; the rest of the app uses a plain service. Risk 2 is resolved and the
onboarding screen already had the download as step ③.

No pair is installed out of the box — **first run always downloads.**

## 5. Apple Intelligence is off on the development machine

```
availability: unavailable(.appleIntelligenceNotEnabled)
```

Graceful degradation is not a hypothetical. "Explain" must be absent rather
than broken, and captions must work without it. Testing that path costs
nothing right now because it is the default state here.

## 6. No app bundle is needed

`bundle id: <none>` — every API above works in a plain SwiftPM executable.

## 7. The hang was ours, not Apple's

The first two probes hung forever. Cause: **top-level code in `main.swift` is
implicitly `@MainActor`, so `Task { }` inherits main-actor isolation** — and
`DispatchSemaphore.wait()` on the main thread meant the task could never be
scheduled. Rewriting as `@main struct` with `static func main() async` fixed it.
Nothing to do with Speech or Translation.

## Still open

**Latency — risk 1, the one that decides whether the product exists.** Needs
audio through `SpeechAnalyzer`. Next.

---

# Latency — measured

13.3 s of English speech fed at wall-clock pace, exactly as a live tap would.
Lag = (result arrived) − (word was spoken), from `.audioTimeRange` attributes.
Source: `Spike/Sources/latency/Latency.swift`.

## Result

**69 results · median 0.32 s · p90 0.78 s.**

Transcription is not the bottleneck. Against the 2.5 s acceptance criterion
this leaves roughly 1.7 s of budget for translation.

## The finding that matters more than the number

**Volatile results already carry sentence punctuation.**

```
[live]  lag 0.17s — So let's circle back on the runway before we commit to Q3.
[final] lag 1.11s — So let's circle back on the runway before we commit to Q3.
```

The full stop arrives with the volatile result. The final adds **nothing but
delay** — and sometimes makes the text worse:

```
[live]  lag 0.33s — ...before the off site, but the runway is tighter...
[final] lag 4.52s — ...before the of site, but the runway is tighter...
```

4.52 s, and "off site" became "of site".

**So Bilby must cut clauses from volatile results and never wait for
`isFinal`.** Waiting would blow the entire latency budget on the slowest
sentences and buy worse text.

## A real bug this exposed

`ClauseBuffer` reset its emitted offset whenever an utterance got shorter,
assuming the transcriber had started over. Real finals are shorter *because
they reword what was already shown* — so the reset re-emitted the whole
sentence and the same line would have reached the screen twice.

Fixed: shown text is never revisited. Covered by
`finalDoesNotDuplicate`, built from the exact transcript above.

Found before a single line of UI existed. This is what the spike was for.

## Caveats

- `say` audio is clean and synthetic. Real calls are compressed, accented and
  overlapping; expect worse accuracy and somewhat worse lag. Re-measure on a
  recorded Zoom call before trusting these numbers.
- **Translation latency is still unmeasured** — no language pack is installed,
  and installing one needs the SwiftUI download path. The 2.5 s criterion is
  not yet proven end to end.

---

# Translation — measured, and the latency question is settled

Language pair installed through the SwiftUI path inside a real `.app`.
Source: `Spike/Sources/prepare/Prepare.swift`.

## Latency

```
prepared in 179 s          ← one-time download
0.706 s   (first call, warm-up)
0.109 s
0.067 s
median 0.109 s
```

**End to end: 0.32 s transcription + 0.11 s translation ≈ 0.43 s median.**

Acceptance criterion 1 wanted under 2.5 s. We are inside it by roughly 5×.
**Risk 1 is retired: Bilby is a caption bar, not a transcript viewer.**

## What installing actually requires

Three things had to be true at once, and each was discovered by failing:

1. **A real `.app` bundle.** A SwiftUI executable without one is treated as a
   background process — no window ever appears and `.translationTask` never
   fires. `Spike/Scripts/make-app.sh` builds the minimal bundle.
2. **The SwiftUI `.translationTask` path.** From a plain process
   `prepareTranslation()` fails in 11 ms with `.notInstalled` and downloads
   nothing.
3. **Both sides of the pair.** The system dialog downloaded English (US) *and*
   Russian, even though English speech recognition was already installed.

What the user downloads in System Settings does not satisfy the framework:
those assets are tagged `SAFBundleIdentifier = com.apple.Translate`.

**The download UI is Apple's**, presented by the system and not stylable. Our
onboarding can only trigger it and frame it. It took **3 minutes**, so the app
must stay usable while it runs rather than blocking on a progress bar.

## The quality finding — this is the important one

```
"circle back on the runway"  →  "вернемся на взлетно-посадочную полосу"
"the runway is tighter"      →  "взлетно-посадочная полоса плотнее"
```

**Runway became an airport runway.** Apple's NMT translates a clause in
isolation, so financial jargon collapses into its literal sense — and it does
so in precisely the meetings where the captions were needed.

This was the predicted failure mode, now confirmed on the first real sentence
tried. It means:

- The fast line will be **fast and sometimes wrong**, and wrong in a way the
  reader cannot detect.
- **"Explain with context" is not a bonus feature. It is the product.** It is
  the only thing that repairs this, and it is what no open-source caption bar
  has.
- It must be tested against Apple Intelligence, which is **switched off** on
  the development machine. That is now a blocking dependency for M5, not a
  nice-to-have.

`TranslationSession` is also **non-Sendable**, so the translator adapter must
own it inside a single isolation domain rather than pass it around.
