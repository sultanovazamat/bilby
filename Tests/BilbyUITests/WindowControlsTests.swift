import Testing

@testable import BilbyUI

@Suite("Window controls")
struct WindowControlsTests {
    @Test("the bar can be expanded but not collapsed further")
    func barControls() {
        #expect(WindowControl.close.isEnabled(in: .bar))
        #expect(WindowControl.expand.isEnabled(in: .bar))
        #expect(!WindowControl.collapse.isEnabled(in: .bar))
    }

    @Test("the panel can be collapsed but not expanded further")
    func panelControls() {
        #expect(WindowControl.close.isEnabled(in: .panel))
        #expect(WindowControl.collapse.isEnabled(in: .panel))
        #expect(!WindowControl.expand.isEnabled(in: .panel))
    }

    @Test("the three buttons are in the order macOS puts them")
    func order() {
        #expect(WindowControl.allCases == [.close, .collapse, .expand])
    }
}

@Suite("Following the live sentence")
struct LiveFollowTests {
    @Test("a new list follows the live sentence and offers no way back to it")
    func startsFollowing() {
        let follow = LiveFollow()
        #expect(follow.isFollowing)
        #expect(!follow.showsJump)
    }

    @Test("scrolling up stops the list following and offers the way back")
    func scrollingUpStops() {
        var follow = LiveFollow()
        follow.scrolled(toBottom: false, userInitiated: true)
        #expect(!follow.isFollowing)
        #expect(follow.showsJump)
    }

    @Test("scrolling back to the bottom resumes following on its own")
    func scrollingBackResumes() {
        var follow = LiveFollow()
        follow.scrolled(toBottom: false, userInitiated: true)
        follow.scrolled(toBottom: true, userInitiated: true)
        #expect(follow.isFollowing)
        #expect(!follow.showsJump)
    }

    @Test("the way back resumes following, so later sentences keep arriving")
    func jumpResumes() {
        var follow = LiveFollow()
        follow.scrolled(toBottom: false, userInitiated: true)
        follow.jumped()
        #expect(follow.isFollowing)
        #expect(!follow.showsJump)
    }

    @Test("content growth and resizing do not stop following")
    func layoutDoesNotStopFollowing() {
        var follow = LiveFollow()
        follow.scrolled(toBottom: false, userInitiated: false)
        #expect(follow.isFollowing)
        #expect(!follow.showsJump)
    }

    @Test("new content does not resume following while reading earlier sentences")
    func layoutPreservesReadingPosition() {
        var follow = LiveFollow()
        follow.scrolled(toBottom: false, userInitiated: true)
        follow.scrolled(toBottom: false, userInitiated: false)
        #expect(!follow.isFollowing)
        #expect(follow.showsJump)
    }

    @Test("the jump animation does not cancel the resumed follow")
    func jumpKeepsFollowingDuringAnimation() {
        var follow = LiveFollow()
        follow.scrolled(toBottom: false, userInitiated: true)
        follow.jumped()
        follow.scrolled(toBottom: false, userInitiated: false)
        #expect(follow.isFollowing)
        #expect(!follow.showsJump)
    }
}
