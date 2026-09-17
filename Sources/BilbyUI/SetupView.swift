import BilbyCore
import SwiftUI

/// What the app can do, and what stands in the way.
///
/// Modelled on how Ice handles permissions: say what the grant enables rather
/// than what the grant is called, poll the real state so granting in System
/// Settings is noticed without a restart, and never trap the user — there is
/// always a way onward, honestly labelled.
@MainActor
@Observable
public final class SetupModel {
    public enum Step: Sendable { case welcome, permission, language, ready }

    public private(set) var step: Step = .welcome
    public private(set) var hasAudioAccess = false
    public private(set) var languageName = ""
    public private(set) var isDownloading = false

    private let checkAudio: @Sendable () -> Bool
    private let openSettings: () -> Void
    private var poll: Timer?

    public init(
        checkAudio: @escaping @Sendable () -> Bool,
        openSettings: @escaping () -> Void
    ) {
        self.checkAudio = checkAudio
        self.openSettings = openSettings
        self.hasAudioAccess = checkAudio()
    }

    public func advance() {
        switch step {
        case .welcome: step = .permission; watchPermission()
        case .permission: step = .language
        case .language: step = .ready
        case .ready: break
        }
    }

    public func requestAudioAccess() {
        // Asking and checking are the same act: building a tap is what raises
        // the prompt. If it was already refused, the prompt will not return, so
        // send the user where the switch lives.
        if !checkAudio() { openSettings() }
    }

    /// Granting happens in System Settings, outside this app, so the only way
    /// to notice is to keep looking.
    private func watchPermission() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = self.checkAudio()
                if granted != self.hasAudioAccess { self.hasAudioAccess = granted }
                if granted, self.step == .permission { self.poll?.invalidate() }
            }
        }
    }

    public func stopWatching() { poll?.invalidate(); poll = nil }
}

public struct SetupView: View {
    @Bindable private var model: SetupModel
    private let onFinish: () -> Void

    public init(model: SetupModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            BilbyMark()
                .fill(.primary)
                .frame(width: 54, height: 54)
                .padding(.bottom, 20)
            content
            Spacer(minLength: 16)
            footer
        }
        .padding(28)
        .frame(width: 460, height: 380)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            page(
                title: "Captions for any call",
                lines: [
                    "Bilby listens to what an app is playing and shows it in your language, live.",
                    "Everything happens on this Mac. Nothing is uploaded.",
                    "Your microphone is never used.",
                ]
            )
        case .permission:
            page(
                title: "Let Bilby hear your calls",
                lines: [
                    "Read what Zoom, Meet or a browser is playing.",
                    "Caption a video without headphones getting in the way.",
                ],
                status: model.hasAudioAccess ? "Allowed" : "Not allowed yet"
            )
        case .language:
            page(
                title: "Choose your language",
                lines: [
                    "Captions are translated on this Mac, with no account and no network.",
                    "The first language takes about three minutes to download.",
                ]
            )
        case .ready:
            page(
                title: "Ready",
                lines: [
                    "Bilby lives in the menu bar. Pick an app and it starts listening.",
                    "Captions appear at the bottom of the screen, and stay hidden when you share it.",
                ]
            )
        }
    }

    private func page(title: String, lines: [String], status: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 22, weight: .semibold, design: .rounded))
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "circle.fill")
                    .labelStyle(BulletLabel())
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let status {
                Label(status, systemImage: model.hasAudioAccess ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.hasAudioAccess ? .green : .secondary)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if model.step == .permission, !model.hasAudioAccess {
                Button("Open System Settings") { model.requestAudioAccess() }
            }
            Spacer()
            // Never a dead end: the wording says what continuing will cost.
            Button(continueTitle) {
                if model.step == .ready { onFinish() } else { model.advance() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var continueTitle: String {
        switch model.step {
        case .ready: "Start listening"
        case .permission where !model.hasAudioAccess: "Continue without sound"
        default: "Continue"
        }
    }
}

private struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 4)).foregroundStyle(.tertiary)
            configuration.title
        }
    }
}
