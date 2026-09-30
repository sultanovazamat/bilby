import AppKit
import BilbyCore
import BilbyUI
import Foundation
import SwiftUI

/// `swift run BilbyPreview` checks the mark at actual menu-bar sizes.
/// Add `--output <directory>` for light/dark PNGs and every onboarding scene.
/// Add `--repo-assets` to export just the README and social-preview images.
@main
struct Preview {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--icon") {
            let out = URL(filePath: "Bilby.iconset")
            try Icon.writeIconSet(to: out)
            print("wrote \(out.path)")
            return
        }
        for (side, listening) in [(18, false), (18, true), (32, false)] {
            render(CGFloat(side), listening: listening)
            print()
        }
        guard let flag = CommandLine.arguments.firstIndex(of: "--output"),
            CommandLine.arguments.indices.contains(flag + 1)
        else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        if CommandLine.arguments.contains("--repo-assets") {
            try RepositoryImages.write(to: directory)
            print("Wrote repository images to \(directory.path)")
            return
        }
        try save(MarkSheet(), to: directory.appendingPathComponent("bilby-mark.png"))
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            func snap(_ model: SetupModel, _ name: String) throws {
                let view = SetupView(model: model, onFinish: {}).environment(\.colorScheme, scheme)
                try save(view, to: directory.appendingPathComponent("setup-\(name)-\(appearance).png"))
            }
            // Walks the real model the way a user would, so every scene is
            // one the app can actually reach.
            let model = SetupModel(
                checkAudio: { .granted }, openSettings: {}, startListening: {},
                loadLanguages: {
                    [
                        .init(code: "es", name: "Spanish", isInstalled: false),
                        .init(code: "fr", name: "French", isInstalled: true),
                    ]
                }, selectedLanguageCode: "es"
            )
            try snap(model, "welcome")
            model.advance()
            await model.requestAudioAccess()
            try snap(model, "permission")
            let quiet = SetupModel(checkAudio: { .nothingToProbe }, openSettings: {}, startListening: {})
            quiet.advance()
            await quiet.requestAudioAccess()
            try snap(quiet, "permission-nothing-playing")
            quiet.stopWatching()
            model.advance()
            await model.loadLanguages()
            try snap(model, "language")
            model.prepareLanguage()
            try snap(model, "download")
            if let request = model.preparation {
                model.completePreparation(
                    request, error: "The language couldn’t be prepared. Check your connection and try again.")
            }
            try snap(model, "retry")
            model.prepareLanguage()
            if let request = model.preparation { model.completePreparation(request, error: nil) }
            model.advance()
            model.update(readiness: .ready)
            try snap(model, "tryIt")
            model.update(readiness: .downloading(0.43))
            try snap(model, "tryIt-downloading")
            model.update(readiness: .preparing(0.4))
            try snap(model, "tryIt-loading")
            model.update(
                readiness: .failed(
                    "Speech recognition needs a one-time download. Connect to the internet and try again."))
            try snap(model, "tryIt-failed")
            model.update(readiness: .ready)
            model.show(PreviewCaptions.source, PreviewCaptions.translation)
            try snap(model, "caption")
            model.stopWatching()
        }
        // The history panel's content, with a session's worth of sentences.
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            let model = PreviewCaptions.history()
            let view = HistoryView(model: model, perform: { _ in })
                .frame(width: 380, height: 520)
                .environment(\.colorScheme, scheme)
            try save(view, to: directory.appendingPathComponent("history-\(appearance).png"))

            // The bar, over something to be read against, at both ends of
            // the size range so the type stays legible at each.
            for size in [TextSize.small, .medium, .large] {
                model.type = size.type(systemScale: 1)
                let bar = CaptionBar(model: model, perform: { _ in })
                    .frame(width: model.type.barWidth(within: 1400))
                    .padding(26)
                    .background(scheme == .dark ? Color(white: 0.11) : Color(white: 0.92))
                    .environment(\.colorScheme, scheme)
                try save(bar, to: directory.appendingPathComponent("bar-\(size.rawValue)-\(appearance).png"))
            }
            model.type = TextSize.medium.type(systemScale: 1)
        }
        print("Wrote previews to \(directory.path)")
    }

    static func render(_ side: CGFloat, listening: Bool) {
        print("── \(Int(side))pt\(listening ? ", listening" : "") ──")
        let image = BilbyMark.menuBarImage(side: side, listening: listening)
        guard let data = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else { return }
        let shades = Array(" .:-=+*#%@")
        for y in 0..<bitmap.pixelsHigh {
            var line = ""
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let shade = shades[min(Int(alpha * Double(shades.count - 1)), shades.count - 1)]
                line.append(shade)
                line.append(shade)
            }
            print(line)
        }
    }

    @MainActor
    static func save(_ view: some View, to url: URL) throws {
        // ImageRenderer omits AppKit-backed controls such as the language
        // picker. Capture the actual hosting view, including those controls.
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // One turn of the run loop: images and AppKit controls need a display
        // pass before they are in the cache.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        window.close()
    }
}

private struct MarkSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            row(scheme: .light)
            row(scheme: .dark)
        }
        .frame(width: 520)
    }

    private func row(scheme: ColorScheme) -> some View {
        HStack(alignment: .bottom, spacing: 42) {
            ForEach([18, 24, 32, 80], id: \.self) { side in
                VStack(spacing: 16) {
                    BilbyMark().fill(.primary)
                        .frame(width: CGFloat(side), height: CGFloat(side))
                    Text("\(side)pt").font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .frame(width: 520, height: 176)
        .background(scheme == .light ? Color.white : Color(white: 0.08))
        .environment(\.colorScheme, scheme)
    }
}
