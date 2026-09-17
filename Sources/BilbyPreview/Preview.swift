import AppKit
import BilbyUI
import Foundation
import SwiftUI

/// `swift run BilbyPreview` checks the silhouette at actual menu-bar sizes.
/// Add `--output <directory>` for light/dark PNGs and every onboarding scene.
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
        for side in [18, 32] {
            render(CGFloat(side))
            print()
        }
        guard let flag = CommandLine.arguments.firstIndex(of: "--output"),
            CommandLine.arguments.indices.contains(flag + 1)
        else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        try save(MarkSheet(), to: directory.appendingPathComponent("bilby-mark.png"))
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            for step in SetupModel.Step.allCases {
                let model = SetupModel(
                    checkAudio: { true }, openSettings: {}, startListening: {},
                    loadLanguages: {
                        [
                            .init(code: "ru", name: "Russian", isInstalled: step == .tryIt),
                            .init(code: "fr", name: "French", isInstalled: true),
                        ]
                    }
                )
                if step != .welcome { model.advance() }
                if step == .language || step == .tryIt {
                    model.requestAudioAccess()
                    await model.loadLanguages()
                }
                if step == .tryIt { model.advance() }
                let view = SetupView(model: model, onFinish: {})
                    .environment(\.colorScheme, scheme)
                try save(view, to: directory.appendingPathComponent("setup-\(step)-\(appearance).png"))
                if step == .language {
                    model.prepareLanguage()
                    try save(view, to: directory.appendingPathComponent("setup-download-\(appearance).png"))
                    if let request = model.preparation {
                        model.completePreparation(
                            request, error: "The language couldn’t be prepared. Check your connection and try again.")
                    }
                    try save(view, to: directory.appendingPathComponent("setup-retry-\(appearance).png"))
                }
                if step == .tryIt {
                    model.show(
                        "Let’s make sure everyone can follow the conversation.",
                        "Давайте убедимся, что все могут следить за разговором.")
                    try save(view, to: directory.appendingPathComponent("setup-caption-\(appearance).png"))
                }
                model.stopWatching()
            }
        }
        print("Wrote previews to \(directory.path)")
    }

    static func render(_ side: CGFloat) {
        print("── \(Int(side))pt ──")
        let image = BilbyMark.menuBarImage(side: side)
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
    private static func save(_ view: some View, to url: URL) throws {
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
