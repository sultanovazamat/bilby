import BilbyCore
import SwiftUI

/// First run, shaped by what actually makes onboarding work: prime every
/// permission before asking, defer everything that can wait, and end on a
/// meaningful first action rather than a summary.
///
/// The last step is the point. Instead of describing what Bilby does, it does
/// it — the user plays anything with speech and watches captions appear inside
/// this window. An empty state that fills itself is worth more than three
/// screens explaining that it would.
@MainActor
@Observable
public final class SetupModel {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, permission, language, tryIt

        var title: String {
            switch self {
            case .welcome: "Captions for any call"
            case .permission: "Let Bilby hear your calls"
            case .language: "Read in your language"
            case .tryIt: "Play something"
            }
        }
    }

    public private(set) var step: Step = .welcome
    public private(set) var hasAudioAccess = false
    public private(set) var languages: [String] = []
    public private(set) var caption: (source: String, translation: String)?

    private let checkAudio: @Sendable () -> Bool
    private let openSettings: () -> Void
    private let startListening: () -> Void
    private var poll: Timer?

    public init(
        checkAudio: @escaping @Sendable () -> Bool,
        openSettings: @escaping () -> Void,
        startListening: @escaping () -> Void
    ) {
        self.checkAudio = checkAudio
        self.openSettings = openSettings
        self.startListening = startListening
        self.hasAudioAccess = checkAudio()
    }

    public var canContinue: Bool {
        step != .tryIt || caption != nil
    }

    public func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.smooth(duration: 0.3)) { step = next }
        if next == .permission { watchPermission() }
        if next == .tryIt { startListening() }
    }

    public func show(_ source: String, _ translation: String) {
        withAnimation(.smooth(duration: 0.2)) { caption = (source, translation) }
    }

    public func requestAudioAccess() {
        if !checkAudio() { openSettings() }
    }

    /// Granting happens outside this app, so the only way to notice is to keep
    /// looking — and then move on without making the user press anything.
    private func watchPermission() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = self.checkAudio()
                guard granted != self.hasAudioAccess else { return }
                withAnimation(.smooth) { self.hasAudioAccess = granted }
                if granted, self.step == .permission {
                    self.poll?.invalidate()
                    try? await Task.sleep(for: .milliseconds(600))
                    self.advance()
                }
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
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(30)
        .frame(width: 480, height: 420)
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: 16) {
            BilbyMark()
                .fill(.primary)
                .frame(width: model.step == .welcome ? 68 : 40)
                .frame(height: model.step == .welcome ? 68 : 40)
                .animation(.smooth(duration: 0.35), value: model.step)

            Text(model.step.title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .contentTransition(.opacity)
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            points([
                "Hear what any app is playing and read it in your language, live.",
                "Everything happens on this Mac. Nothing is uploaded.",
                "Your microphone is never used.",
            ])

        case .permission:
            VStack(alignment: .leading, spacing: 18) {
                points([
                    "Read what Zoom, Meet or a browser is playing.",
                    "Caption a video without taking your headphones off.",
                ])
                HStack(spacing: 8) {
                    Image(systemName: model.hasAudioAccess ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(model.hasAudioAccess ? .green : .secondary)
                    Text(model.hasAudioAccess ? "Allowed — carrying on" : "Waiting for permission…")
                        .foregroundStyle(model.hasAudioAccess ? .primary : .secondary)
                }
                .font(.system(size: 13, weight: .medium))
            }

        case .language:
            points([
                "Captions are translated here, with no account and no network.",
                "The first language takes about three minutes to arrive.",
                "You can change it any time from the menu bar.",
            ])

        case .tryIt:
            VStack(alignment: .leading, spacing: 16) {
                Text("Start a video or a call. Captions appear below — and on screen, at the bottom.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // The empty state fills itself. That is the whole argument for
                // this app, made in the only way that convinces anyone.
                VStack(alignment: .leading, spacing: 6) {
                    if let caption = model.caption {
                        Text(caption.source)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(caption.translation)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                    } else {
                        Text("Listening…")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                .padding(14)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func points(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().frame(width: 4, height: 4).foregroundStyle(.tertiary)
                    Text(line).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            // Where you are, without a word about it.
            HStack(spacing: 6) {
                ForEach(SetupModel.Step.allCases, id: \.self) { step in
                    Circle()
                        .frame(width: 5, height: 5)
                        .foregroundStyle(step == model.step ? .primary : .quaternary)
                }
            }

            Spacer()

            if model.step == .permission, !model.hasAudioAccess {
                Button("Open Settings") { model.requestAudioAccess() }
            }

            Button(continueTitle) {
                if model.step == .tryIt { onFinish() } else { model.advance() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.step == .tryIt && !model.canContinue)
        }
        .padding(.top, 20)
    }

    private var continueTitle: String {
        switch model.step {
        case .welcome: "Get started"
        case .permission where !model.hasAudioAccess: "Skip for now"
        case .tryIt: "Done"
        default: "Continue"
        }
    }
}
