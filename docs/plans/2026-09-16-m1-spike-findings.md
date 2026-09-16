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
