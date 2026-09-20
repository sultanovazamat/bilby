import Testing

@testable import BilbyUI

@Suite("Resources")
struct UIResourcesTests {
    @Test("the onboarding screenshots load without Bundle.module")
    func screenshotsLoad() {
        #expect(UIResources.bundle != nil)
        #expect(UIResources.screenshot(named: "menu-bar") != nil)
        #expect(UIResources.screenshot(named: "menu-sources") != nil)
        #expect(UIResources.screenshot(named: "missing") == nil)
    }
}
