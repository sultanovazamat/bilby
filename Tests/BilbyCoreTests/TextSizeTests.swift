import Testing

@testable import BilbyCore

@Suite("Text size")
struct TextSizeTests {
    @Test("an untouched system means the sizes the app was drawn at")
    func systemDefault() {
        let type = TextSize.system.type(systemScale: 1)
        #expect(type == TextSize.medium.type(systemScale: 1))
        #expect(type.line == CaptionType.baseLine)
    }

    @Test("a reader who already asked macOS for large captions gets them here")
    func followsTheSystem() {
        let large = TextSize.system.type(systemScale: 1.5)
        #expect(large.line > TextSize.medium.type(systemScale: 1).line)
        #expect(large.historyTranslation > large.historySource)
    }

    @Test("choosing a size here ignores what the system says")
    func overrideWins() {
        #expect(TextSize.small.type(systemScale: 2) == TextSize.small.type(systemScale: 0.5))
        #expect(TextSize.small.type(systemScale: 1).line < TextSize.large.type(systemScale: 1).line)
    }

    @Test("nothing unreadable or absurd gets through")
    func clamped() {
        #expect(TextSize.system.type(systemScale: 0.1).line >= CaptionType.baseLine * CaptionType.smallest)
        #expect(TextSize.system.type(systemScale: 9).line <= CaptionType.baseLine * CaptionType.biggest)
    }

    @Test("the bar widens with the text, but never past the screen")
    func widthFollowsButIsCapped() {
        let big = TextSize.large.type(systemScale: 1)
        #expect(big.barWidth(within: 5000) > CaptionType.baseWidth)
        #expect(big.barWidth(within: 700) == 700)
    }
}
