import SwiftUI

/// Four short scenes, ending with real captions. Motion lives in the view so
/// Reduce Motion applies equally to transitions, progress, and illustrations.
public struct SetupView: View {
    @Bindable private var model: SetupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    private let onFinish: () -> Void

    public init(model: SetupModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                BilbyMark().fill(.primary).frame(width: 22, height: 22)
                Text("bilby").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }
            .accessibilityElement(children: .combine)

            ZStack(alignment: .top) {
                scene
                    .id(model.step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 24)),
                                removal: .opacity.combined(with: .offset(x: -16))
                            ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 24)

            footer
        }
        .padding(.horizontal, 34)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 520, height: 580)
        .background(.background)
        .animation(reduceMotion ? nil : .smooth(duration: 0.38), value: model.step)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.caption?.translation)
        .task(id: model.step) {
            titleFocused = true
            switch model.step {
            case .permission:
                // A tap probe can raise the system prompt. Let the explanation
                // finish appearing before making the first probe.
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                await model.watchPermission()
            case .language:
                await model.loadLanguages()
            default: break
            }
        }
    }

    private var scene: some View {
        VStack(spacing: 18) {
            // Real screenshots of the real app. A drawn approximation teaches
            // the shape of an idea; a photograph of the thing teaches where to
            // click. Bilby has no Dock icon, so knowing where it lives is not
            // a detail — it is the difference between using it and losing it.
            Group {
                if let name = model.step.screenshot, let shot = UIResources.screenshot(named: name) {
                    Image(nsImage: shot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                } else {
                    SetupIllustration(step: model.step, isReady: model.canContinue)
                }
            }
            .frame(height: 152)
            .accessibilityHidden(true)

            VStack(spacing: 9) {
                Text(model.step.title)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        switch model.step {
        case .welcome: "Bilby lives in the menu bar, with no icon in the Dock.\nClick it whenever you want captions."
        case .permission: "Bilby needs permission to hear audio from other apps.\nYour microphone is never used."
        case .language: "Choose the language you’d like to read.\nTranslation happens right here on your Mac."
        case .tryIt: "Click Bilby in the menu bar, choose what to listen to,\nand captions appear at the bottom of your screen."
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 13) {
                detail("Always in the menu bar, never in the Dock", symbol: "menubar.arrow.up.rectangle")
                detail("Works with the apps you already use", symbol: "macwindow")
                detail("Your audio stays on this Mac", symbol: "lock.shield")
                detail("No account. No microphone.", symbol: "mic.slash")
            }
            .padding(.top, 8)
        case .permission:
            VStack(alignment: .leading, spacing: 10) {
                Label("Allow system audio in the macOS prompt.", systemImage: "speaker.wave.2")
                Text(
                    "If access was denied, open System Settings → Privacy & Security → Screen & System Audio Recording and allow Bilby."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                Text("No prompt? Play audio in another app. We’ll continue automatically when access is allowed.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        case .language:
            languageContent
        case .tryIt:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    model.caption == nil ? "Listening for your first words" : "Your live captions",
                    systemImage: "waveform"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                if let caption = model.caption {
                    Text(caption.source)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(caption.translation)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .lineLimit(3)
                } else {
                    Text("Try a browser video with speech. Keep its sound on.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        }
    }

    private var languageContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoadingLanguages {
                ProgressView("Finding languages…").controlSize(.small)
            } else if !model.languages.isEmpty {
                Picker(
                    "Translate English into",
                    selection: Binding(
                        get: { model.selectedLanguageCode },
                        set: { model.selectLanguage($0) }
                    )
                ) {
                    ForEach(model.languages) { language in
                        Text(language.isInstalled ? "\(language.name) — ready" : language.name)
                            .tag(language.code)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.preparation != nil)
            }

            if model.preparation != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing your language…").font(.system(size: 13))
                    Spacer()
                    Button("Cancel") { model.cancelPreparation() }.font(.system(size: 12))
                }
                Text("Confirm the macOS download sheet. The first download may take a few minutes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if let error = model.languageError {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Label(
                    model.canContinue
                        ? "Ready for offline translation" : "One download, then you can translate offline.",
                    systemImage: model.canContinue ? "checkmark.circle.fill" : "arrow.down.circle"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func detail(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(SetupModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= model.step.rawValue ? Color.primary : Color.primary.opacity(0.12))
                        .frame(width: step == model.step ? 20 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.step.rawValue + 1) of 4")
            Spacer()
            Button(actionTitle, action: performAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(actionDisabled)
        }
        .padding(.top, 18)
    }

    private var actionTitle: String {
        switch model.step {
        case .welcome: return "Get started"
        // A button labelled "Open Settings" that does nothing because
        // permission is already granted is a broken button. It has to say what
        // pressing it will do, given the state it is actually in.
        case .permission: return model.hasAudioAccess ? "Continue" : "Open Settings"
        case .language:
            if model.isLoadingLanguages { return "Loading…" }
            if model.preparation != nil { return "Preparing…" }
            if model.languages.isEmpty { return "Try again" }
            if model.canContinue { return model.finishesAfterLanguage ? "Done" : "Try live captions" }
            return model.languageError == nil ? "Download language" : "Retry download"
        case .tryIt: return "Start using Bilby"
        }
    }

    private var actionDisabled: Bool {
        switch model.step {
        case .language: model.isLoadingLanguages || model.preparation != nil
        default: false
        }
    }

    private func performAction() {
        switch model.step {
        case .permission:
            if model.hasAudioAccess { model.advance() } else { model.requestAudioAccess() }
        case .language where model.languages.isEmpty:
            Task { await model.loadLanguages() }
        case .language where !model.canContinue: model.prepareLanguage()
        case .language where model.finishesAfterLanguage: onFinish()
        case .tryIt: onFinish()
        default: model.advance()
        }
    }
}
