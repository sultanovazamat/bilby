import AppKit
import BilbyCore
import SwiftUI
import Testing

@testable import BilbyUI

@Suite("History scrolling", .serialized)
@MainActor
struct HistoryViewTests {
    @Test("opening an overflowing transcript shows the latest sentence")
    func opensAtLatest() throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for index in 0..<30 {
            for event in engine.consume(Utterance("Sentence \(index).", isFinal: true)) { model.apply(event) }
        }
        let history = HostedHistory(model: model)
        defer { history.window.close() }
        history.layout()
        let geometry = try #require(history.geometry)
        #expect(geometry.contentSize.height > geometry.containerSize.height)
        #expect(history.isAtBottom)
    }

    @Test("a translation that grows beyond the viewport keeps its last line visible", arguments: [false, true])
    func followsTranslation(settled: Bool) throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        if settled {
            for event in engine.consume(Utterance("The sentence being spoken.", isFinal: true)) { model.apply(event) }
        } else {
            model.apply(.live("The sentence being spoken."))
        }
        let history = HostedHistory(model: model)
        defer { history.window.close() }
        history.layout()
        #expect(history.isAtBottom)

        let translation = String(repeating: "A long translated sentence. ", count: 40)
        if settled {
            model.apply(.translated(try #require(model.latest?.id), translation))
        } else {
            model.apply(.draft(translation))
        }
        history.layout()
        let geometry = try #require(history.geometry)
        #expect(geometry.contentSize.height > geometry.containerSize.height)
        #expect(history.isAtBottom)
    }

    @Test("live words and new sentences keep following after history reaches its limit")
    func followsCappedHistory() throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for index in 0..<CaptionModel.historyLimit {
            for event in engine.consume(Utterance("Sentence \(index).", isFinal: true)) { model.apply(event) }
        }
        let history = HostedHistory(model: model)
        defer { history.window.close() }
        history.layout()
        #expect(history.isAtBottom)

        for event in engine.consume(Utterance("The next sentence.", isFinal: true)) { model.apply(event) }
        history.layout()
        #expect(model.lines.count == CaptionModel.historyLimit)
        #expect(history.isAtBottom)

        model.apply(.live(String(repeating: "More words arrive. ", count: 30)))
        history.layout()
        #expect(history.isAtBottom)

        history.window.setContentSize(NSSize(width: 280, height: 240))
        history.layout()
        #expect(history.isAtBottom, "bottom gap after resize: \(history.bottomGap)")
    }

    @Test("scrolling up holds the reading position and scrolling down resumes following", arguments: [false, true])
    func userControlsFollowing(phased: Bool) throws {
        let model = CaptionModel()
        model.apply(.live(String(repeating: "The sentence being spoken. ", count: 40)))
        let history = HostedHistory(model: model)
        defer { history.window.close() }
        history.layout()
        try history.scroll(by: 200, phased: phased)
        #expect(!history.isAtBottom)
        let offset = try #require(history.geometry?.contentOffset.y)

        model.apply(.draft(String(repeating: "A long translated sentence. ", count: 40)))
        history.layout()
        #expect(!history.isAtBottom)
        #expect(abs(try #require(history.geometry?.contentOffset.y) - offset) < 2)

        try history.scroll(by: -10_000, phased: phased)
        #expect(history.isAtBottom)
        model.apply(.draft(String(repeating: "A long translated sentence. ", count: 80)))
        history.layout()
        #expect(history.isAtBottom)
    }

    @Test("the arrow jumps to the latest sentence and keeps following later translations")
    func arrowResumesFollowing() throws {
        let model = CaptionModel()
        model.apply(.live(String(repeating: "The sentence being spoken. ", count: 40)))
        let history = HostedHistory(model: model)
        defer { history.window.close() }
        history.window.orderFront(nil)
        history.layout()
        try history.scroll(by: 200)
        #expect(!history.isAtBottom)

        try history.clickJumpArrow()
        // Allow the animated jump to finish, then add more content.
        let deadline = Date().addingTimeInterval(2)
        while !history.isAtBottom, Date() < deadline { history.layout() }
        #expect(history.isAtBottom)
        model.apply(.draft(String(repeating: "A long translated sentence. ", count: 40)))
        history.layout()
        #expect(history.isAtBottom)
    }
}

/// Hosts the real view so the tests exercise SwiftUI layout and its scroll
/// callbacks, not just the small follow policy in isolation.
@MainActor
private final class HostedHistory {
    let window: NSWindow
    var geometry: ScrollGeometry?

    init(model: CaptionModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = HistoryView(model: model, perform: { _ in })
            .onScrollGeometryChange(for: ScrollGeometry.self) {
                $0
            } action: { [weak self] _, geometry in
                self?.geometry = geometry
            }
        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = []
        window.contentView = host
    }

    var isAtBottom: Bool {
        bottomGap <= 24
    }

    var bottomGap: CGFloat {
        guard let geometry else { return .infinity }
        return geometry.contentSize.height - geometry.visibleRect.maxY
    }

    func layout() {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func clickJumpArrow() throws {
        let content = try #require(window.contentView)
        // The 30-point arrow has 14 points of inset from each bottom corner.
        let location = NSPoint(x: content.bounds.width - 29, y: 29)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    func scroll(by delta: Int32, phased: Bool = true) throws {
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let content = try #require(window.contentView)
        let scroll = try #require(scrollView(in: content))
        // Deliver a wheel gesture only to this test window; nothing is
        // posted to the system or to a running copy of Bilby.
        let events = phased ? [(1, Int32(0)), (2, delta), (4, Int32(0))] : [(0, delta)]
        for (phase, amount) in events {
            let event = try #require(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
            layout()
        }
    }
}
