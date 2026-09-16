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
