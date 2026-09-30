import AppKit
import SwiftUI
import Testing

@testable import BilbyUI

@MainActor
@Suite("Caption windows")
struct CaptionWindowsTests {
    /// The owner's call, on 2026-10-01: a recording or a screenshot of a
    /// captions app should have its captions in it. They were hidden from all
    /// capture, which on macOS is one switch for screen sharing, screenshots
    /// and screen recordings alike.
    @Test("the bar and the column show up in screenshots, recordings and screen sharing")
    func capturable() {
        _ = NSApplication.shared
        #expect(CaptionPanel(content: EmptyView()).sharingType == .readOnly)
        #expect(HistoryPanel(content: EmptyView()).sharingType == .readOnly)
    }
}
