# Which recogniser — settled by measurement

Date: 2026-09-16.

## The candidates

| Engine | Live latency | Punctuation | Languages | Size |
|---|---|---|---|---|
| Apple `SpeechTranscriber` | **bursts every 3.60 s** | yes | 9 | 0 |
| Parakeet EOU 120M | **0.16 s** | no | 25 | 220 MB |
| Parakeet Unified 0.6B | 2.08 s | yes | English only | — |
| Parakeet TDT v3 sliding | ~1 s / 10 s to confirm | no | 25 | ~2 GB |

Apple's figure is measured on a live call: five to nine sentences inside
200 ms, then a still screen. Median time a caption was readable: **0.05 s**.
No interface fixes a 3.6 s delivery cadence.

Parakeet Unified's 2.08 s is from its own source: context [70, 13, 13]
encoder frames = 5.6 s left / 1.04 s chunk / 1.04 s right.

FluidAudio's own benchmark: Unified streaming 2.21% WER **with** punctuation
and capitals; TDT v3 2.6% **without**. (A correction: TDT v3's vocabulary
contains six punctuation tokens, but the model does not use them — the
vocabulary is not the answer, the benchmark is.)

## Does punctuation matter to us? No — measured

The streaming EOU model's vocabulary has **1026 tokens and zero punctuation**,
against 8192 tokens for the batch model. Punctuation was traded away for
160 ms latency and a fifth of the size.

Buying it back costs 2.08 s and 24 of the 25 languages. So: is it worth
anything? Translating the same lines with and without punctuation, **cut into
clauses first, as Bilby actually does**:

| Clause, no punctuation | Translation |
|---|---|
| i did it for you | Я сделал это для тебя |
| i didnt ask | Я не спрашивал |
| how do you tell someone its over | Как сказать кому-то, что все кончено**?** |
| you send them a notarized letter | Вы отправляете им нотариально заверенное письмо |
| website check please | Проверьте сайт, пожалуйста |

**Word for word identical to the punctuated version, bar the trailing full
stop.** The translator restores the question mark and the internal commas
itself, in the target language, where they belong.

Punctuation only mattered when two sentences were fed as one string — which
Bilby never does, because `ClauseBuffer` cuts them apart first. Our clause
cutting already provides the only thing punctuation was needed for.

## Decision

**Parakeet EOU 120M.** 160 ms, 25 source languages including Russian, 220 MB.
No punctuation, and we now know that costs us nothing.

Apple stays available in the menu so the comparison can be repeated rather
than argued about.

---

# Revision, 2026-09-17: punctuation is required after all

The conclusion above — that punctuation buys us nothing — was right about what
it measured and wrong about what mattered.

That test compared punctuated and unpunctuated **whole clauses**. It never
asked where a clause comes from. Without punctuation the engine gives no
sentence boundary, so Bilby had to invent one, and every invention failed:

| Guess | Result |
|---|---|
| Cut on a full stop | Parakeet EOU emits none |
| Cut every 12 words | "it wasn't" / "really that risky" — the screen said the opposite |
| Cut on a 450 ms pause | better, but a pause is not a sentence |
| Wait for `<EOU>` | fired once in ninety seconds of monologue |

Apple's translator is good on whole sentences and bad on fragments: given
"i knew that i could / do it again" it produced «Сделай это снова», an
imperative. Measured separately, Apple also beat Opus-MT (77M) on our own
transcript, so the translator is not the weak link — **the cut is.**

**Punctuation is not wanted as formatting. It is the only trustworthy sentence
boundary**, and it has to come from the model that heard the speech.

## Requirement

Punctuation and capitalisation from the recogniser. **English-only source is
acceptable** — the case is an English meeting read in Russian, so the 25
languages EOU offered were never the point.

## Current answer

**Parakeet Unified 0.6B** — 596 MB, streaming, punctuated, English.
About a second of latency against EOU's 160 ms. Downloaded and wired as a
third engine so the three can be compared on the same call.

If a second proves too slow, the two-tier shape already in the code takes EOU
for the live line and Unified for the settled one.

---

# Revision, 2026-09-21: multilingual tried, measured, rejected

Nemotron 3.5 streaming multilingual 0.6B was built into the app as a second
engine, switchable from the menu, and run against Parakeet Unified on the
same material. Both promises from its model card held: it punctuates
natively, and it covers forty language locales, detecting which is being
spoken rather than being told. It lost on the two things this product is
actually made of. It was slower, and it was less accurate.

Slower is structural, not incidental. It publishes no word timings while
streaming, so the pause rule has nothing to measure and its own punctuation
is the only boundary it offers. And that punctuation is documented to thin
out over a long session below a 1120 ms chunk, against 320 ms for Parakeet
Unified. About a second of the gap is the chunk tier, and the chunk tier is
not a dial we can turn down without losing the punctuation that justified
the model in the first place.

So: English only, and the MVP is built on that. Worth revisiting when the
model exposes streaming timings, or ships a smaller chunk that keeps its
punctuation — not before, and not from reading another model card. The
earlier claim in this document that multilingual models cannot punctuate
was wrong, and so was the first reading of this one. Both were settled by
running them.
