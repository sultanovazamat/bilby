import Foundation
@preconcurrency import Translation

/// Does missing punctuation actually hurt the translation?
///
/// Parakeet's streaming EOU model emits no punctuation and no capitals. Buying
/// them back costs 2.08 s of latency and 24 of the 25 languages, so it is worth
/// knowing whether they change the Russian at all before paying that.
@main
struct Punct {
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        let pairs = [
            ("So let's circle back on the runway before we commit to Q3.",
             "so lets circle back on the runway before we commit to q3"),
            ("We should ship the beta before the offsite, but the runway is tighter than we thought.",
             "we should ship the beta before the offsite but the runway is tighter than we thought"),
            ("I did it for you. I didn't ask.",
             "i did it for you i didnt ask"),
            ("How do you tell someone it's over? You send them a notarized letter.",
             "how do you tell someone its over you send them a notarized letter"),
            ("Website check, please. You, my friend, are winning handsomely.",
             "website check please you my friend are winning handsomely"),
        ]
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ru")
        )
        // Bilby never translates two sentences as one string: ClauseBuffer cuts
        // them apart first. So the fair comparison is punctuated-whole against
        // unpunctuated-but-already-cut.
        let cut = [
            ["i did it for you", "i didnt ask"],
            ["how do you tell someone its over", "you send them a notarized letter"],
            ["website check please", "you my friend are winning handsomely"],
        ]
        print("=== unpunctuated, but cut into clauses first ===")
        for clauses in cut {
            for clause in clauses {
                let text = (try? await session.translate(clause).targetText) ?? "—"
                print("  \(clause)\n    → \(text)")
            }
        }
        print("\n=== whole strings, for contrast ===")

        for (punctuated, bare) in pairs {
            let a = (try? await session.translate(punctuated).targetText) ?? "—"
            let b = (try? await session.translate(bare).targetText) ?? "—"
            print("\nEN  \(punctuated)")
            print("с пунктуацией  \(a)")
            print("без            \(b)")
            print(a == b ? "→ идентично" : "→ различается")
        }
    }
}
