# First Run, Menu, and History Panel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the built app survive another Mac, remove the dead ends from the first run, give the menu state and plain-language status, and add a side panel that keeps sentence history.

**Architecture:** Every decision stays in pure, string-testable types: `SetupModel` for the first run, `CaptionModel` for what the bar and the panel show, a new `MenuState` for the menu, and `StatusText` for sentences shown to people. Apple frameworks stay at the edges (`BilbySources`, the AppKit windows, `BilbyApp`). Resources are found by a resolver that never crashes instead of SwiftPM's generated accessor.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit, SwiftPM, Swift Testing, FluidAudio 0.12 (Parakeet Unified), Apple Translation, ServiceManagement.

Design: `docs/plans/2026-09-20-first-run-menu-and-history-panel-design.md`.

Conventions for every task:
- Tests live in `Tests/BilbyUITests` and use Swift Testing (`@Test`, `#expect`). Run one file with `swift test --filter <SuiteName>`; the whole suite with `swift test`.
- The purity gate `./Scripts/check-core-purity.sh` must stay green: `BilbyCore` imports no framework.
- Commit after each task with a sentence-case title and a short body saying why, ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- The branch is `first-run-and-history-panel`.

---

## Part 1 — the app survives another Mac

### Task 1: A resource resolver that cannot crash

**Files:**
- Create: `Sources/BilbyUI/UIResources.swift`
- Test: `Tests/BilbyUITests/UIResourcesTests.swift`

**Step 1: Write the failing test**

```swift
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
```

**Step 2: Run it to verify it fails**

Run: `swift test --filter Resources`
Expected: compile error, `cannot find 'UIResources' in scope`.

**Step 3: Write the resolver**

```swift
import AppKit
import Foundation

/// Where BilbyUI's images live at runtime.
///
/// SwiftPM's generated `Bundle.module` looks in exactly two places: the top
/// level of the app bundle, where a signed app cannot keep a bundle, and the
/// absolute path of the build directory on the machine that built it. Both
/// miss a real installation, and a miss is a fatalError on the first
/// onboarding page. This looks where `make-app.sh` puts the bundle and where
/// SwiftPM leaves it for tests and tools, and answers nil rather than
/// crashing.
enum UIResources {
    private final class Marker {}

    static let bundle: Bundle? = {
        let name = "Bilby_BilbyUI.bundle"
        let candidates = [
            Bundle.main.resourceURL,  // Bilby.app/Contents/Resources
            Bundle.main.bundleURL,  // a bare executable: beside it
            Bundle(for: Marker.self).bundleURL.deletingLastPathComponent(),  // tests: beside the .xctest
        ]
        for directory in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: directory.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }()

    /// A screenshot by name. An `NSImage`, not SwiftUI's `Image(_:bundle:)`:
    /// the latter draws nothing for a loose PNG in a SwiftPM bundle — it
    /// rendered an empty frame — while `image(forResource:)` draws it.
    static func screenshot(named name: String) -> NSImage? {
        bundle?.image(forResource: name)
    }
}
```

**Step 4: Run the test**

Run: `swift test --filter Resources`
Expected: `✔ Test "the onboarding screenshots load without Bundle.module" passed`. If `bundle` is nil under the test host, print the three candidate paths in the test and add the one that contains `Bilby_BilbyUI.bundle`; do not add the absolute build path.

**Step 5: Commit**

```bash
git add Sources/BilbyUI/UIResources.swift Tests/BilbyUITests/UIResourcesTests.swift
git commit -m "Find the resource bundle where the app keeps it"
```

### Task 2: Draw the screenshots

**Files:**
- Modify: `Sources/BilbyUI/SetupView.swift:69-83`

**Step 1: Replace the image branch**

Replace the `Group { if let shot = model.step.screenshot { Image(shot, bundle: .module) ...` block with:

```swift
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
```

**Step 2: Render and look**

Run: `swift run BilbyPreview --output .build/previews && open .build/previews/setup-welcome-light.png`
Expected: the welcome page shows the menu bar photograph, not an empty square. (The preview driver is fixed in Task 4; until then only `welcome` is trustworthy.)

**Step 3: Commit**

```bash
git add Sources/BilbyUI/SetupView.swift
git commit -m "Show the menu bar photographs instead of an empty frame"
```

### Task 3: Build scripts that ship what they built, and a portability gate

**Files:**
- Modify: `Scripts/make-app.sh`
- Modify: `Scripts/release.sh`
- Create: `Scripts/check-app-portable.sh`

**Step 1: Rewrite `Scripts/make-app.sh`**

```bash
#!/bin/bash
# A SwiftUI executable without a bundle is treated as a background process:
# no window appears and the system presents no dialogs. Wrap it in a real .app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Not inside ~/Desktop: an app that lives there triggers a Desktop-access
# prompt merely by reading its own resource bundle, and a captions app asking
# to see your files looks exactly as alarming as it sounds.
APP="${BILBY_APP_PATH:-$HOME/Applications/Bilby.app}"
# debug while developing; release.sh asks for release.
CONFIG="${BILBY_CONFIG:-debug}"
BUILD="$ROOT/.build/$CONFIG"
mkdir -p "$(dirname "$APP")"

swift build -c "$CONFIG" --product Bilby --package-path "$ROOT" >/dev/null
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Bilby" "$APP/Contents/MacOS/Bilby"
cp "$ROOT/Resources/Bilby.icns" "$APP/Contents/Resources/Bilby.icns"

# SwiftPM emits resources as bundles beside the executable. Contents/Resources
# is the only place a signed app may keep them, and UIResources looks there.
# SwiftPM's own Bundle.module would not: it checks the app's top level and then
# the absolute build path of this checkout — which is why the app used to run
# here and crash on every other Mac. check-app-portable.sh guards against that.
for bundle in "$BUILD"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Bilby</string>
  <key>CFBundleIconFile</key><string>Bilby</string>
  <key>CFBundleIdentifier</key><string>net.variant.bilby</string>
  <key>CFBundleName</key><string>Bilby</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Bilby reads what your meeting app is playing so it can caption and translate it. Nothing leaves this Mac, and your microphone is never used.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
```

**Step 2: Create `Scripts/check-app-portable.sh`**

```bash
#!/bin/bash
# The built app must not depend on this checkout. SwiftPM's resource accessor
# falls back to the absolute build path, which once hid a launch crash on
# every Mac but the one that built it. Run the app with this directory
# unreadable and require it to stay alive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/Bilby.app}"
LOG="$(mktemp)"
sandbox-exec -p "(version 1)(allow default)(deny file-read* (subpath \"$ROOT\"))" \
    "$APP/Contents/MacOS/Bilby" >"$LOG" 2>&1 &
PID=$!
sleep 6
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "✓ $APP runs without $ROOT"
else
    echo "✗ $APP died without $ROOT:"
    cat "$LOG"
    exit 1
fi
```

Then `chmod +x Scripts/check-app-portable.sh`.

**Step 3: Rewrite the build section of `Scripts/release.sh`**

Replace the lines from `"$ROOT/Scripts/make-app.sh" >/dev/null` through `cp -R "$ROOT/.build/Bilby.app" "$APP"` with:

```bash
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
# Build straight into the staging folder: the image must hold the app that
# was just built, not whatever an earlier run left in .build.
BILBY_CONFIG=release BILBY_APP_PATH="$APP" "$ROOT/Scripts/make-app.sh" >/dev/null
"$ROOT/Scripts/check-app-portable.sh" "$APP"
```

**Step 4: Verify**

Run: `./Scripts/make-app.sh && ./Scripts/check-app-portable.sh`
Expected: `✓ /Users/…/Applications/Bilby.app runs without /Users/…/bilby`. Before Task 1 this printed the `Fatal error: could not load resource bundle` line; if it still does, the bundle is not in `Contents/Resources`.

Run: `./Scripts/release.sh`
Expected: a release build (several minutes the first time), the portability line, `signature verified`, and `.build/Bilby.dmg (…)`. If the release configuration fails to build FluidAudio, report it and keep `BILBY_CONFIG=debug` in release.sh with a comment.

**Step 5: Commit**

```bash
git add Scripts/make-app.sh Scripts/release.sh Scripts/check-app-portable.sh
git commit -m "Ship the app that was just built, and prove it runs without the checkout"
```

### Task 4: Tests that match the intended onboarding, and a page that does not probe when closed

**Files:**
- Modify: `Sources/BilbyUI/SetupModel.swift:67-81` (init), `:126-138` (`watchPermission`)
- Modify: `Tests/BilbyUITests/SetupModelTests.swift:26-38`, `:55-61`
- Modify: `Sources/BilbyPreview/Preview.swift:29-67`

**Step 1: Rewrite the two stale tests**

Replace `existingGrantAdvances` (lines 26–38) with:

```swift
    @Test("an existing audio grant is confirmed on the page, and continues on the next step")
    func existingGrantIsConfirmed() {
        var openedSettings = false
        let model = SetupModel(
            checkAudio: { true }, openSettings: { openedSettings = true }, startListening: {}
        )
        model.advance()
        model.requestAudioAccess()
        #expect(model.hasAudioAccess)
        #expect(model.step == .permission)
        #expect(!openedSettings)
        model.advance()
        #expect(model.step == .language)
        model.stopWatching()
    }
```

Replace `existingGrantAdvancesOnAppearance` (lines 55–61) with:

```swift
    @Test("a grant that exists on arrival is shown as granted, not skipped past")
    func grantOnArrivalIsConfirmed() async {
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {},
            pollInterval: .milliseconds(1)
        )
        model.advance()
        let watching = Task { await model.watchPermission() }
        while !model.hasAudioAccess { await Task.yield() }
        #expect(model.step == .permission)
        model.stopWatching()
        await watching.value
    }
```

**Step 2: Run to verify they fail**

Run: `swift test --filter Onboarding`
Expected: compile error, `extra argument 'pollInterval' in call`, plus the `closedPermissionPage` failure seen before (`checks → 1`).

**Step 3: Add the poll interval and the guard**

In `SetupModel`, add a stored `private let pollInterval: Duration` and an init parameter `pollInterval: Duration = .seconds(1)` after `selectedLanguageCode`, assigned in the body. Then change `watchPermission()`:

```swift
    public func watchPermission() async {
        // A closed page must not probe: probing is what raises the prompt.
        guard isActive, step == .permission else { return }
        let grantedOnArrival = checkAudio()
        hasAudioAccess = grantedOnArrival

        while isActive, step == .permission, !Task.isCancelled {
            do { try await Task.sleep(for: pollInterval) } catch { return }
            guard isActive, step == .permission else { return }
            let granted = checkAudio()
            guard granted != hasAudioAccess else { continue }
            hasAudioAccess = granted
            if granted, !grantedOnArrival { advance() }
        }
    }
```

**Step 4: Run the suite**

Run: `swift test`
Expected: `Test run with 41 tests in 5 suites passed`. Nothing hangs.

**Step 5: Fix the preview driver**

In `Sources/BilbyPreview/Preview.swift`, replace the `for scheme in …` loop body (lines 29–67) with a driver that walks the real model:

```swift
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            func snap(_ model: SetupModel, _ name: String) throws {
                let view = SetupView(model: model, onFinish: {}).environment(\.colorScheme, scheme)
                try save(view, to: directory.appendingPathComponent("setup-\(name)-\(appearance).png"))
            }
            let model = SetupModel(
                checkAudio: { true }, openSettings: {}, startListening: {},
                loadLanguages: {
                    [
                        .init(code: "ru", name: "Russian", isInstalled: false),
                        .init(code: "fr", name: "French", isInstalled: true),
                    ]
                }
            )
            try snap(model, "welcome")
            model.advance()
            model.requestAudioAccess()
            try snap(model, "permission")
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
            try snap(model, "tryIt")
            model.show(
                "Let’s make sure everyone can follow the conversation.",
                "Давайте убедимся, что все могут следить за разговором.")
            try snap(model, "caption")
            model.stopWatching()
        }
```

Also in `save(_:to:)`, after the first `host.layoutSubtreeIfNeeded()` add `RunLoop.main.run(until: Date().addingTimeInterval(0.1))` and a second `host.layoutSubtreeIfNeeded()`, so images and AppKit controls have a display pass before capture.

**Step 6: Render and look at every scene**

Run: `swift run BilbyPreview --output .build/previews && ls .build/previews`
Expected: `setup-language-light.png` shows the language picker, `setup-tryIt-light.png` the last page with the sources photograph, `setup-caption-light.png` the same with a Russian line. Open them.

**Step 7: Commit**

```bash
git add Sources/BilbyUI/SetupModel.swift Tests/BilbyUITests/SetupModelTests.swift Sources/BilbyPreview/Preview.swift
git commit -m "Tests that match the onboarding as built, and a closed page that never probes"
```

---

## Part 2 — the first run and daily feedback

### Task 5: Setup is done when the last page is reached, and can start at the language page

**Files:**
- Modify: `Sources/BilbyUI/SetupModel.swift` (init, `canContinue`)
- Modify: `Sources/BilbyUI/SetupView.swift` (`actionTitle`, `actionDisabled`, `performAction`)
- Modify: `Sources/BilbyApp/BilbyApp.swift:90-146` (`showSetup`)
- Test: `Tests/BilbyUITests/SetupModelTests.swift`

**Step 1: Write the failing tests**

Add to `SetupModelTests`:

```swift
    @Test("the last page can always be left, caption or not")
    func lastPageAlwaysContinues() async {
        let model = makeModel()
        await reachLanguages(model)
        model.selectLanguage("fr")
        model.advance()
        #expect(model.step == .tryIt)
        #expect(model.canContinue)
        #expect(model.isComplete)
    }

    @Test("setup opened for a language starts there and finishes there")
    func startsAtLanguage() async {
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {},
            loadLanguages: { [.init(code: "fr", name: "French", isInstalled: true)] },
            startingAt: .language
        )
        #expect(model.step == .language)
        #expect(model.finishesAfterLanguage)
        #expect(!model.isComplete)
        await model.loadLanguages()
        #expect(model.canContinue)
    }
```

In `downloadIsRequired`, the lines after `#expect(model.step == .tryIt)` become:

```swift
        #expect(chosen == "ru")
        #expect(starts == 1)
        #expect(model.canContinue)
        model.show("Hello", "Привет")
        #expect(model.caption?.translation == "Привет")
```

**Step 2: Run to verify they fail**

Run: `swift test --filter Onboarding`
Expected: compile errors for `startingAt`, `finishesAfterLanguage`, `isComplete`.

**Step 3: Implement**

In `SetupModel`:

```swift
    /// Where the window opened. Opened for a language from the menu, it ends
    /// after the download instead of replaying welcome and permission.
    public let startedAt: Step
    public var finishesAfterLanguage: Bool { startedAt == .language }
    /// Reaching the last page is finishing: closing the window from there
    /// must not bring the whole flow back at the next launch.
    public var isComplete: Bool { step == .tryIt }
```

Add `startingAt: Step = .welcome` to `init` (before `pollInterval`), set `step = startingAt` and `startedAt = startingAt`. In `canContinue`, `case .tryIt: return true`.

In `SetupView`:
- `actionTitle`, case `.language`: after the `Try again` line, `if model.canContinue { return model.finishesAfterLanguage ? "Done" : "Try live captions" }`.
- `actionDisabled`: drop the `.tryIt` case.
- `performAction`: add `case .language where model.finishesAfterLanguage: onFinish()` after the `!model.canContinue` case, and make the `.tryIt` case `onFinish()` unconditionally.

In `BilbyApp.swift`, replace `showSetup(languageCode:)` with:

```swift
    /// Shown once at first launch, and afterwards for a language download,
    /// which needs a window for Apple's sheet.
    func showSetup(at step: SetupModel.Step = .welcome, language: String? = nil) {
        if let setup, step == .welcome {
            setup.present()
            return
        }
        setup?.close()
        let model = SetupModel(
            checkAudio: { AudioPermission.isGranted },
            openSettings: { [weak self] in self?.openPermissionSettings() },
            startListening: { [weak self] in self?.listenToWhateverPlays() },
            loadLanguages: {
                await Languages.available().map {
                    SetupModel.LanguageChoice(code: $0.code, name: $0.name, isInstalled: $0.isInstalled)
                }
            },
            selectTarget: { [weak self] code in self?.chooseTarget(code) },
            selectedLanguageCode: language ?? target?.code,
            startingAt: step
        )
        setupModel = model
        let content = SetupView(model: model) { [weak self] in
            self?.markSetUp()
            self?.setup?.close()
        }
        .background { SetupLanguageDownload(model: model) }
        let window = SetupWindow(
            content: content,
            onClose: { [weak self] in
                if model.isComplete { self?.markSetUp() }
                model.stopWatching()
                self?.setupListening?.cancel()
                self?.setupListening = nil
                self?.setupModel = nil
                self?.setup = nil
            })
        setup = window
        window.present()
    }

    private func markSetUp() { UserDefaults.standard.set(true, forKey: "didSetUp") }

    func openPermissionSettings() {
        if let url = AudioPermission.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// The last setup page listens for real, to whichever app is playing.
    private func listenToWhateverPlays() {
        setupListening?.cancel()
        setupListening = Task { [weak self] in
            while let self, !Task.isCancelled {
                refreshSources()
                if let source = sources.first(where: \.isPlaying) {
                    listen(to: source)
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
```

`translate(into:)` becomes `showSetup(at: .language, language: language.code)` for an uninstalled language. (`target` becomes optional in Task 7; until then use `target.code`.)

**Step 4: Run the suite**

Run: `swift test`
Expected: all pass, 43 tests.

**Step 5: Commit**

```bash
git add Sources/BilbyUI/SetupModel.swift Sources/BilbyUI/SetupView.swift Sources/BilbyApp/BilbyApp.swift Tests/BilbyUITests/SetupModelTests.swift
git commit -m "Setup finishes when its last page is reached, and opens at the language page for a download"
```

### Task 6: The speech model becomes visible

**Files:**
- Modify: `Sources/BilbyCore/Models.swift` (add `Readiness`)
- Modify: `Sources/BilbySources/AudioTranscribing.swift:14-26`
- Modify: `Sources/BilbySources/UnifiedTranscriber.swift:34-43`
- Create: `Sources/BilbyUI/StatusText.swift`
- Modify: `Sources/BilbyUI/CaptionModel.swift`, `Sources/BilbyUI/CaptionBar.swift`
- Modify: `Sources/BilbyUI/SetupModel.swift`, `Sources/BilbyUI/SetupView.swift` (last page)
- Modify: `Sources/BilbyApp/BilbyApp.swift` (`warmUp`, `menuOpened`, `start`)
- Test: `Tests/BilbyUITests/StatusTextTests.swift`, `Tests/BilbyUITests/SetupModelTests.swift`

**Step 1: Write the failing tests**

`Tests/BilbyUITests/StatusTextTests.swift`:

```swift
import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Status text")
struct StatusTextTests {
    @Test("waiting text names the phase in plain words")
    func waiting() {
        #expect(StatusText.waiting(readiness: .idle, app: "Zoom") == "Getting ready…")
        #expect(StatusText.waiting(readiness: .preparing, app: "Zoom") == "Getting ready…")
        #expect(StatusText.waiting(readiness: .downloading(0.427), app: "Zoom") == "Downloading speech recognition, 43%")
        #expect(StatusText.waiting(readiness: .ready, app: "Zoom") == "Listening to Zoom…")
        #expect(StatusText.waiting(readiness: .ready, app: nil) == "Listening…")
        #expect(StatusText.waiting(readiness: .failed("No network."), app: "Zoom") == "No network.")
    }
}
```

Add to `SetupModelTests`:

```swift
    @Test("reaching the language page asks for the recogniser once, and retry asks again")
    func warmsUpOnce() async {
        var warmUps = 0
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {},
            loadLanguages: { [.init(code: "fr", name: "French", isInstalled: true)] },
            warmUp: { warmUps += 1 }
        )
        model.advance()
        model.requestAudioAccess()
        model.advance()
        #expect(warmUps == 1)
        model.advance()
        #expect(warmUps == 1)
        model.update(readiness: .failed("No network."))
        model.retryWarmUp()
        #expect(warmUps == 2)
        #expect(model.readiness == .preparing)
    }
```

**Step 2: Run to verify they fail**

Run: `swift test --filter "Status text|Onboarding"`
Expected: compile errors for `StatusText`, `warmUp:`, `update(readiness:)`.

**Step 3: `Readiness` in the core**

Append to `Sources/BilbyCore/Models.swift`:

```swift
/// How far the speech recogniser is from being able to caption.
public enum Readiness: Equatable, Sendable {
    case idle
    /// Fetching the model, 0…1. Happens once per machine.
    case downloading(Double)
    /// Compiling for this machine. Nothing to report until it is done.
    case preparing
    case ready
    /// One sentence a person can act on. The full error is in the log.
    case failed(String)

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
    /// Ready or failed: a warm-up that has finished one way or the other.
    public var isSettled: Bool { self == .ready || isFailure }
}
```

**Step 4: `StatusText`**

```swift
import BilbyCore

/// Sentences for people, from states the pipeline reports in its own terms.
/// Every string a user reads about the pipeline's state is made here, so it
/// can be tested and so the raw counters and Core Audio codes stay in the log.
public enum StatusText {
    /// Before the first words arrive, in the bar and on the last setup page.
    public static func waiting(readiness: Readiness, app: String?) -> String {
        switch readiness {
        case .idle, .preparing: return "Getting ready…"
        case .downloading(let fraction):
            return "Downloading speech recognition, \(Int((fraction * 100).rounded()))%"
        case .failed(let message): return message
        case .ready: return app.map { "Listening to \($0)…" } ?? "Listening…"
        }
    }
}
```

**Step 5: The transcriber reports progress**

In `AudioTranscribing.swift`, replace the `warmUp()` requirement and its default with:

```swift
    /// Loads the models before anyone asks for captions, reporting how far
    /// along it is, and returns the final state.
    ///
    /// Unified takes 50 s on a cold start and 580 MB on a fresh machine.
    /// Doing that silently inside the listening task meant the bar stayed
    /// invisible and the menu said "no audio" while the model downloaded.
    func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness
}

extension AudioTranscribing {
    public func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness { .ready }
}
```

In `UnifiedTranscriber.swift`, replace `warmUp()` with:

```swift
    public func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness {
        let started = ContinuousClock.now
        Log.write("asr: warming up…")
        progress(.preparing)
        do {
            try await StreamingUnifiedAsrManager(config: config).loadModels(
                to: nil, configuration: nil,
                progressHandler: { update in
                    // Below 1 the files are still arriving. At 1 CoreML compiles
                    // for this machine, which reports nothing until it is done.
                    progress(update.fractionCompleted < 1 ? .downloading(update.fractionCompleted) : .preparing)
                })
            Log.write("asr: warm in \(ContinuousClock.now - started)")
            progress(.ready)
            return .ready
        } catch {
            Log.write("asr: FAILED to warm — \(error)")
            let failed = Readiness.failed(Self.explain(error))
            progress(failed)
            return failed
        }
    }

    /// One sentence a person can act on. The error itself goes to the log.
    static func explain(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        let offline = ["offline", "internet", "network", "hostname", "-1009", "-1001", "timed out"]
        if offline.contains(where: text.contains) {
            return "Speech recognition needs a one-time download. Connect to the internet and try again."
        }
        return "Speech recognition couldn’t be set up. Try again."
    }
```

**Step 6: The caption model carries a status line**

In `CaptionModel`, add `public var status: String?` with the comment "Shown while the bar has no words: what Bilby is doing instead." Clear it in `clear()` and in `apply(.live(text))` when `text` is not empty.

In `CaptionBar`, change `isEmpty` to `hidden`:

```swift
    private var hidden: Bool { isEmpty && model.status == nil }
```

and add, inside the `VStack` after the translation block:

```swift
            if isEmpty, let status = model.status {
                Label(status, systemImage: "waveform")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
```

Use `hidden` in the three modifiers that used `isEmpty` (`opacity`, `scaleEffect`, `blur`) and in the `.animation(value:)`.

**Step 7: The setup model asks for warm-up and shows readiness**

In `SetupModel`: add `public private(set) var readiness: Readiness = .idle`, a `private let warmUp: () -> Void`, a `private var hasWarmedUp = false`, and an init parameter `warmUp: @escaping () -> Void = {}`. Then:

```swift
    /// Asked for once, when the user has committed by reaching the language
    /// page, so the recogniser is usually ready by the last page.
    public func ensureWarm() {
        guard isActive, !hasWarmedUp else { return }
        hasWarmedUp = true
        readiness = .preparing
        warmUp()
    }

    public func retryWarmUp() {
        guard isActive else { return }
        readiness = .preparing
        warmUp()
    }

    public func update(readiness: Readiness) {
        self.readiness = readiness
    }
```

In `advance()`, after `step = next`: `if next == .language { ensureWarm() }`. In `init`, after the assignments: `if startingAt.rawValue >= Step.language.rawValue { ensureWarm() }`.

In `SetupView`, the `.tryIt` content becomes:

```swift
        case .tryIt:
            VStack(alignment: .leading, spacing: 8) {
                Label(tryItHeading, systemImage: "waveform")
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
                } else if case .failed(let message) = model.readiness {
                    Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("Retry") { model.retryWarmUp() }.font(.system(size: 12))
                } else if case .downloading = model.readiness {
                    Text("About 600 MB, once. Bilby works offline after this.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
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
```

with

```swift
    private var tryItHeading: String {
        if model.caption != nil { return "Your live captions" }
        if model.readiness == .ready { return "Listening for your first words" }
        return StatusText.waiting(readiness: model.readiness, app: nil)
    }
```

**Step 8: The delegate owns one warm-up**

In `BilbyApp.swift` replace `isWarm`, `warmUp()` and the body of `menuOpened()` with:

```swift
    private(set) var readiness: Readiness = .idle {
        didSet {
            setupModel?.update(readiness: readiness)
            refreshStatus()
        }
    }
    @ObservationIgnored private var warming: Task<Readiness, Never>?

    /// Loads the recogniser once. Listening awaits the same task, so pressing
    /// Start during a download waits for it instead of starting a second one.
    @discardableResult
    func warm() -> Task<Readiness, Never> {
        if let warming, !readiness.isFailure { return warming }
        readiness = .preparing
        let transcriber = UnifiedTranscriber()
        let task = Task.detached { [weak self] () -> Readiness in
            let final = await transcriber.warmUp { partial in
                Task { @MainActor [weak self] in
                    guard let self, !readiness.isSettled else { return }
                    readiness = partial
                }
            }
            await MainActor.run { [weak self] in self?.readiness = final }
            return final
        }
        warming = task
        return task
    }

    /// Opening the menu means the user is about to act, which is the moment
    /// worth spending on. Warming up at launch cost 14 seconds of CPU and
    /// 400 MB every login, before anyone had asked for anything.
    func menuOpened() {
        refreshSources()
        Task { languages = await Languages.available() }
        warm()
    }

    /// The bar's line while it has no words to show.
    private func refreshStatus() {
        guard isListening, model.lines.isEmpty, model.live.isEmpty else {
            model.status = nil
            return
        }
        model.status = StatusText.waiting(readiness: readiness, app: listening?.name)
    }
```

Pass `warmUp: { [weak self] in self?.warm() }` into `SetupModel` in `showSetup`. In `start()`, the task becomes:

```swift
        running = Task { [weak self] in
            guard let self else { return }
            refreshStatus()
            let ready = await warm().value
            guard ready == .ready, !Task.isCancelled else {
                finish()
                return
            }
            // …existing pipeline body unchanged…
            finish()
        }
```

and add:

```swift
    /// The stream ended, by Stop or by itself. Either way the menu must not
    /// keep offering Stop for something that is no longer running.
    private func finish() {
        isListening = false
        model.clear()
        panel?.orderOut(nil)
    }
```

`stop()` becomes `running?.cancel(); running = nil; finish()`.

**Step 9: Run everything**

Run: `swift test && ./Scripts/check-core-purity.sh`
Expected: all pass; purity green (`Readiness` is a plain enum).

Run: `./Scripts/make-app.sh && open ~/Applications/Bilby.app`, then from the menu Start Captions for a playing app. Expected: the bar appears at once with "Getting ready…" and then "Listening to …", before any words.

**Step 10: Commit**

```bash
git add Sources Tests
git commit -m "Say what the recogniser is doing instead of showing nothing"
```

### Task 7: Language defaults from the system, never from a hard-coded "ru"

**Files:**
- Modify: `Sources/BilbyUI/SetupModel.swift` (init, `loadLanguages`, new `defaultLanguage`)
- Modify: `Sources/BilbyUI/SetupView.swift` (picker placeholder, `actionTitle`)
- Modify: `Sources/BilbyApp/BilbyApp.swift:69` (`target` optional)
- Test: `Tests/BilbyUITests/SetupModelTests.swift`

**Step 1: Write the failing tests**

```swift
    @Test("the default language is the first one the system prefers that Apple can translate into")
    func defaultLanguageFromSystem() async {
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {},
            loadLanguages: {
                [.init(code: "ru", name: "Russian", isInstalled: false), .init(code: "de", name: "German", isInstalled: false)]
            },
            preferredLanguages: ["en-US", "de-DE", "ru-RU"]
        )
        await reachLanguages(model)
        #expect(model.selectedLanguageCode == "de")
    }

    @Test("an English-only system leaves the choice to the user")
    func englishOnlySystem() async {
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {},
            loadLanguages: { [.init(code: "ru", name: "Russian", isInstalled: true)] },
            preferredLanguages: ["en-US", "en-GB"]
        )
        await reachLanguages(model)
        #expect(model.selectedLanguageCode == "")
        #expect(model.selectedLanguage == nil)
        #expect(!model.canContinue)
        model.selectLanguage("ru")
        #expect(model.canContinue)
    }

    @Test("a saved choice beats the system preference")
    func savedChoiceWins() async {
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {},
            loadLanguages: {
                [.init(code: "ru", name: "Russian", isInstalled: true), .init(code: "de", name: "German", isInstalled: true)]
            },
            selectedLanguageCode: "ru", preferredLanguages: ["de-DE"]
        )
        await reachLanguages(model)
        #expect(model.selectedLanguageCode == "ru")
    }
```

Change `makeModel` to pass `selectedLanguageCode: "ru"` explicitly so the existing tests do not depend on this Mac's language list.

**Step 2: Run to verify they fail**

Run: `swift test --filter Onboarding`
Expected: compile error, `extra argument 'preferredLanguages'`.

**Step 3: Implement**

In `SetupModel`: the init parameter becomes `selectedLanguageCode: String? = nil` followed by `preferredLanguages: [String] = Locale.preferredLanguages`; store `self.selectedLanguageCode = selectedLanguageCode ?? ""` and `self.preferredLanguages = preferredLanguages`. Add:

```swift
    /// The first language the user already reads that Apple can translate
    /// into. English is skipped: it is the source, so never the target.
    static func defaultLanguage(preferred: [String], among languages: [LanguageChoice]) -> String? {
        for tag in preferred {
            let code = tag.split(separator: "-").first.map { $0.lowercased() } ?? ""
            if code != "en", languages.contains(where: { $0.code == code }) { return code }
        }
        return nil
    }
```

In `loadLanguages()`, replace the `selectedLanguage == nil` line with:

```swift
        if selectedLanguage == nil {
            selectedLanguageCode = Self.defaultLanguage(preferred: preferredLanguages, among: entries) ?? ""
        }
```

In `SetupView.languageContent`, inside the `Picker`, before the `ForEach`:

```swift
                    if model.selectedLanguageCode.isEmpty {
                        Text("Choose a language").tag("")
                    }
```

In `actionTitle` for `.language`, after the `Try again` line: `if model.selectedLanguage == nil { return "Choose a language" }`, and in `actionDisabled` for `.language` add `|| model.selectedLanguage == nil`.

In `BilbyApp.swift`: `private(set) var target: Language? = UserDefaults.standard.string(forKey: "targetLanguage").map(Language.init)`. In `listen(to:)`, first line: `guard let target else { showSetup(at: .language); return }`, and use `target` where `chosenTarget` was set. `chooseTarget` unchanged.

**Step 4: Run the suite, then commit**

Run: `swift test`
Expected: all pass.

```bash
git add Sources Tests
git commit -m "Default the language to one the user already reads"
```

### Task 8: A permission page with nothing to probe is not a dead end

**Files:**
- Modify: `Sources/BilbyCore/Models.swift` (add `AudioAccess`)
- Modify: `Sources/BilbySources/AudioPermission.swift:22-38`
- Modify: `Sources/BilbyUI/SetupModel.swift` (`checkAudio`, `audio`, `canContinue`, `requestAudioAccess`, `watchPermission`)
- Modify: `Sources/BilbyUI/SetupView.swift` (permission content, `actionTitle`, `performAction`)
- Modify: `Sources/BilbyApp/BilbyApp.swift`, `Sources/BilbyPreview/Preview.swift` (`checkAudio` closures)
- Test: `Tests/BilbyUITests/SetupModelTests.swift`

**Step 1: Write the failing test and migrate the others**

```swift
    @Test("with nothing playing, the page explains and lets the user continue without opening Settings")
    func nothingToProbe() {
        var openedSettings = false
        let model = SetupModel(
            checkAudio: { .nothingToProbe }, openSettings: { openedSettings = true }, startListening: {}
        )
        model.advance()
        model.requestAudioAccess()
        #expect(model.audio == .nothingToProbe)
        #expect(!model.hasAudioAccess)
        #expect(model.canContinue)
        #expect(!openedSettings)
        model.advance()
        #expect(model.step == .language)
        model.stopWatching()
    }
```

Every `checkAudio: { true }` in the file becomes `{ .granted }`, every `{ false }` becomes `{ .refused }`, and the counting closure in `newGrantAdvances` returns `$0 > 1 ? .granted : .refused`.

**Step 2: Run to verify it fails**

Run: `swift test --filter Onboarding`
Expected: compile errors, `.granted` not a member of `Bool`.

**Step 3: Implement**

Append to `Models.swift`:

```swift
/// What a probe of the system-audio permission found.
public enum AudioAccess: Equatable, Sendable {
    case granted
    case refused
    /// No app has played audio yet, so there was nothing to probe and macOS
    /// has not been asked. Not a refusal.
    case nothingToProbe
}
```

`AudioPermission`: rename `isGranted` to `check() -> AudioAccess`, returning `.nothingToProbe` from the guard, `.granted` when `status == noErr`, `.refused` otherwise. Keep `public static var isGranted: Bool { check() == .granted }`.

`SetupModel`: `checkAudio: @escaping @Sendable () -> AudioAccess`; replace `hasAudioAccess` storage with `public private(set) var audio: AudioAccess = .refused` and `public var hasAudioAccess: Bool { audio == .granted }`; `canContinue` for `.permission` is `audio != .refused`; `requestAudioAccess` sets `audio = checkAudio()` and opens Settings only when `.refused`; `watchPermission` compares `AudioAccess` values and advances only on a change to `.granted` when arrival was not `.granted`.

`SetupView`, permission content: when `model.audio == .nothingToProbe` show, in the same box style:

```swift
                Label("Nothing is playing yet, so macOS hasn’t asked.", systemImage: "speaker.slash")
                Text("It will ask the first time you start captions. Allow it then, and Bilby remembers.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
```

`actionTitle` for `.permission`: `.granted` → "Continue", `.nothingToProbe` → "Continue anyway", `.refused` → "Open Settings". `performAction`: `.refused` → `requestAudioAccess()`, otherwise `advance()`.

`BilbyApp.swift`: `checkAudio: { AudioPermission.check() }`. `Preview.swift`: `checkAudio: { .granted }`.

**Step 4: Run the suite, then commit**

```bash
git add Sources Tests
git commit -m "Nothing playing is not a refusal"
```

### Task 9: A menu that shows state, with sentences for people

**Files:**
- Modify: `Sources/BilbyUI/Diagnostics.swift:27-35` (`summary` → `state`)
- Modify: `Sources/BilbyUI/StatusText.swift` (add `problem`, `isPermission`)
- Create: `Sources/BilbyUI/MenuState.swift`
- Modify: `Sources/BilbyUI/BilbyMark.swift:49-58` (listening dot)
- Modify: `Sources/BilbyApp/BilbyApp.swift` (menu, `menu` state, `translate`, `togglePlayback`)
- Test: `Tests/BilbyUITests/MenuStateTests.swift`, `Tests/BilbyUITests/StatusTextTests.swift`

**Step 1: Write the failing tests**

Add to `StatusTextTests`:

```swift
    @Test("pipeline states become one sentence, or nothing when all is well")
    func problems() {
        #expect(StatusText.problem(.flowing(lines: 3), app: "Zoom") == nil)
        #expect(StatusText.problem(.noAudio, app: "Zoom") == "No sound from Zoom yet. Is it muted?")
        #expect(StatusText.problem(.noSpeech(frames: 48_000), app: "Zoom") == "Listening, no speech heard yet")
        #expect(StatusText.problem(.noSentence(utterances: 2), app: "Zoom") == "Listening…")
        #expect(StatusText.problem(.failed("create tap -4 'what'"), app: "Zoom") == "Bilby isn’t allowed to hear other apps.")
        #expect(StatusText.problem(.failed("no default output device"), app: "Zoom") == "Something went wrong. Start captions again.")
    }
```

`Tests/BilbyUITests/MenuStateTests.swift`:

```swift
import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Menu")
struct MenuStateTests {
    let zoom = MenuState.App(id: "us.zoom", name: "Zoom", isPlaying: true)
    let music = MenuState.App(id: "com.apple.Music", name: "Music", isPlaying: false)

    @Test("idle with one app: Start names it, and there is no list to choose from")
    func idleOneApp() {
        var menu = MenuState()
        menu.apps = [zoom]
        #expect(menu.primaryTitle == "Start Captions for Zoom")
        #expect(menu.primaryEnabled)
        #expect(!menu.showsListenTo)
        #expect(menu.statusLine == nil)
    }

    @Test("two apps: the list appears, and the playing one is checked")
    func twoApps() {
        var menu = MenuState()
        menu.apps = [music, zoom]
        #expect(menu.showsListenTo)
        #expect(menu.candidate == zoom)
        #expect(menu.checkedApp == "us.zoom")
    }

    @Test("Start goes back to the app used last when nothing is playing")
    func lastListenedWins() {
        var menu = MenuState()
        menu.apps = [music, MenuState.App(id: "us.zoom", name: "Zoom", isPlaying: false)]
        menu.lastListened = MenuState.App(id: "us.zoom", name: "Zoom", isPlaying: false)
        #expect(menu.primaryTitle == "Start Captions for Zoom")
    }

    @Test("no apps: the item says so and is disabled")
    func noApps() {
        let menu = MenuState()
        #expect(menu.primaryTitle == "No Apps Playing Sound")
        #expect(!menu.primaryEnabled)
    }

    @Test("while running: Stop keeps the name, and the status line reports only trouble")
    func running() {
        var menu = MenuState()
        menu.apps = [zoom]
        menu.listening = zoom
        menu.readiness = .ready
        menu.pipeline = .flowing(lines: 4)
        #expect(menu.primaryTitle == "Stop Captions for Zoom")
        #expect(menu.statusLine == nil)
        menu.pipeline = .noAudio
        #expect(menu.statusLine == "No sound from Zoom yet. Is it muted?")
        menu.readiness = .downloading(0.4)
        #expect(menu.statusLine == "Downloading speech recognition, 40%")
    }

    @Test("a refused tap offers the fix after the session has ended")
    func permissionRefused() {
        var menu = MenuState()
        menu.apps = [zoom]
        menu.lastListened = zoom
        menu.readiness = .ready
        menu.pipeline = .failed("create tap -4 'what'")
        #expect(menu.showsFixPermission)
        #expect(menu.statusLine == "Bilby isn’t allowed to hear other apps.")
    }

    @Test("the language item names the current language and lists only installed ones")
    func languages() {
        var menu = MenuState()
        menu.languages = [
            .init(code: "de", name: "German", isInstalled: false),
            .init(code: "ru", name: "Russian", isInstalled: true),
        ]
        menu.target = "ru"
        #expect(menu.languageTitle == "Language: Russian")
        #expect(menu.installedLanguages.map(\.code) == ["ru"])
        menu.target = nil
        #expect(menu.languageTitle == "Language")
    }
}
```

**Step 2: Run to verify they fail**

Run: `swift test --filter "Menu|Status text"`
Expected: compile errors for `MenuState`, `StatusText.problem`, `Diagnostics.State`.

**Step 3: Diagnostics report a state, not a sentence**

Replace `summary` in `Diagnostics.swift` with:

```swift
    /// Which stage is the first one that is empty.
    public enum State: Equatable, Sendable {
        case failed(String)
        case noAudio
        case noSpeech(frames: Int)
        case noSentence(utterances: Int)
        case flowing(lines: Int)
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        if let failure { return .failed(failure) }
        if frames == 0 { return .noAudio }
        if utterances == 0 { return .noSpeech(frames: frames) }
        if lines == 0 { return .noSentence(utterances: utterances) }
        return .flowing(lines: lines)
    }
```

**Step 4: Sentences for pipeline states**

Add to `StatusText`:

```swift
    /// While captions run: the first stage that is empty, or nil when words
    /// are flowing. A running app should not narrate itself.
    public static func problem(_ state: Diagnostics.State, app: String) -> String? {
        switch state {
        case .flowing: return nil
        case .noAudio: return "No sound from \(app) yet. Is it muted?"
        case .noSpeech: return "Listening, no speech heard yet"
        case .noSentence: return "Listening…"
        case .failed(let reason) where isPermission(reason): return "Bilby isn’t allowed to hear other apps."
        case .failed: return "Something went wrong. Start captions again."
        }
    }

    /// A tap that could not be created is, in practice, a tap macOS refused.
    public static func isPermission(_ reason: String) -> Bool { reason.hasPrefix("create tap") }
```

**Step 5: `MenuState`**

```swift
import BilbyCore

/// Everything the menu shows, computed from plain values so it is tested
/// with strings. The delegate assembles one from its state; the menu reads it.
public struct MenuState: Equatable, Sendable {
    public struct App: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let isPlaying: Bool
        public init(id: String, name: String, isPlaying: Bool) {
            self.id = id
            self.name = name
            self.isPlaying = isPlaying
        }
    }

    public struct Language: Equatable, Sendable, Identifiable {
        public let code: String
        public let name: String
        public let isInstalled: Bool
        public var id: String { code }
        public init(code: String, name: String, isInstalled: Bool) {
            self.code = code
            self.name = name
            self.isInstalled = isInstalled
        }
    }

    public var apps: [App] = []
    /// The app being captioned, while captions run.
    public var listening: App?
    /// The app captioned last, so Start goes back to it.
    public var lastListened: App?
    public var languages: [Language] = []
    public var target: String?
    public var readiness: Readiness = .idle
    public var pipeline: Diagnostics.State = .noAudio

    public init() {}

    /// What Start would pick: the app making sound, else the last one, else the first.
    public var candidate: App? {
        apps.first(where: \.isPlaying) ?? apps.first(where: { $0.id == lastListened?.id }) ?? apps.first
    }

    public var primaryTitle: String {
        if let listening { return "Stop Captions for \(listening.name)" }
        if let candidate { return "Start Captions for \(candidate.name)" }
        return "No Apps Playing Sound"
    }

    public var primaryEnabled: Bool { listening != nil || candidate != nil }

    /// A list is worth showing only when there is a choice to make.
    public var showsListenTo: Bool { apps.count >= 2 }
    public var checkedApp: String? { listening?.id ?? candidate?.id }

    public var installedLanguages: [Language] { languages.filter(\.isInstalled) }
    public var languageTitle: String {
        if let target, let name = languages.first(where: { $0.code == target })?.name {
            return "Language: \(name)"
        }
        return "Language"
    }

    /// One line under the primary item, only when there is something to say.
    public var statusLine: String? {
        if let listening, !readiness.isSettled {
            return StatusText.waiting(readiness: readiness, app: listening.name)
        }
        if case .failed(let message) = readiness { return message }
        if let listening { return StatusText.problem(pipeline, app: listening.name) }
        if case .failed = pipeline, let lastListened { return StatusText.problem(pipeline, app: lastListened.name) }
        return nil
    }

    public var showsFixPermission: Bool {
        if case .failed(let reason) = pipeline { return StatusText.isPermission(reason) }
        return false
    }
}
```

**Step 6: Run the tests**

Run: `swift test --filter "Menu|Status text"`
Expected: all pass.

**Step 7: The icon shows listening**

Replace `menuBarImage` in `BilbyMark.swift`:

```swift
    /// macOS supplies the tint for light, dark, and highlighted menu bars.
    /// While captions run a dot sits at the corner: the only place a menu bar
    /// app can say "on" without words.
    public static func menuBarImage(side: CGFloat = 18, listening: Bool = false) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            NSColor.black.setFill()
            guard listening else {
                NSBezierPath(cgPath: BilbyMark().path(in: rect).cgPath).fill()
                return true
            }
            let mark = CGRect(x: 0, y: 0, width: side * 0.78, height: side * 0.78)
            NSBezierPath(cgPath: BilbyMark().path(in: mark).cgPath).fill()
            let dot = CGRect(x: side * 0.68, y: side * 0.68, width: side * 0.32, height: side * 0.32)
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
```

In `Preview.swift`'s `render(_:)`, render both `listening: false` and `listening: true` at 18 pt and print both, so the dot can be checked by eye in the terminal.

**Step 8: The menu**

In `BilbyApp.swift`, replace the `MenuBarExtra` body and label with:

```swift
        MenuBarExtra {
            // Enumerating Core Audio processes is not free, and warming the
            // model costs seconds. Both happen when the menu opens — the only
            // moment the list has to be right and the user is about to act.
            Color.clear.frame(height: 0).onAppear { delegate.menuOpened() }
            let menu = delegate.menu

            Button(menu.primaryTitle) { delegate.togglePlayback() }
                .keyboardShortcut("p")
                .disabled(!menu.primaryEnabled)
            if let line = menu.statusLine { Text(line) }

            Divider()

            if menu.showsListenTo {
                Menu("Listen To") {
                    ForEach(menu.apps) { app in
                        Toggle(isOn: Binding(get: { menu.checkedApp == app.id }, set: { _ in delegate.listen(toID: app.id) })) {
                            Text(app.isPlaying ? "\(app.name), playing" : app.name)
                        }
                    }
                }
            }

            Menu(menu.languageTitle) {
                ForEach(menu.installedLanguages) { language in
                    Toggle(isOn: Binding(get: { menu.target == language.code }, set: { _ in delegate.translate(into: language.code) })) {
                        Text(language.name)
                    }
                }
                if !menu.installedLanguages.isEmpty { Divider() }
                Button("Add Language…") { delegate.showSetup(at: .language) }
            }

            Toggle("Show Sentence History", isOn: Binding(get: { delegate.showsHistory }, set: { delegate.setHistory($0) }))

            Divider()

            if menu.showsFixPermission {
                Button("Fix Permission…") { delegate.openPermissionSettings() }
            }
            Button("Quit Bilby") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: BilbyMark.menuBarImage(listening: delegate.isListening))
        }
```

(`showsHistory` and `setHistory` arrive in Task 11; until then use a stored `var showsHistory = false` and an empty `setHistory(_:)` so this compiles.)

In the delegate: make `listening` an observed property (drop `@ObservationIgnored`), add `private(set) var pipeline: Diagnostics.State = .noAudio`, set `pipeline = diagnostics.state` in `menuOpened()` and in `finish()`, remove `playTitle` and `problem`, and add:

```swift
    var menu: MenuState {
        func app(_ source: AudioApp) -> MenuState.App {
            MenuState.App(id: source.id, name: source.name, isPlaying: source.isPlaying)
        }
        var state = MenuState()
        state.apps = sources.map(app)
        state.listening = isListening ? listening.map(app) : nil
        state.lastListened = listening.map(app)
        state.languages = languages.map { MenuState.Language(code: $0.code, name: $0.name, isInstalled: $0.isInstalled) }
        state.target = target?.code
        state.readiness = readiness
        state.pipeline = pipeline
        return state
    }

    func togglePlayback() {
        if isListening {
            stop()
        } else if let id = menu.candidate?.id, let source = sources.first(where: { $0.id == id }) {
            listen(to: source)
        }
    }

    func listen(toID id: String) {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        listen(to: source)
    }

    func translate(into code: String) {
        guard languages.first(where: { $0.code == code })?.isInstalled == true else {
            showSetup(at: .language, language: code)
            return
        }
        chooseTarget(code)
        if isListening, let source = listening { listen(to: source) }
    }
```

Delete the stale comment above `MenuBarExtra` ("The icon is the state: a bubble when idle…").

**Step 9: Build, run, look**

Run: `swift build && ./Scripts/make-app.sh && open ~/Applications/Bilby.app`
Expected: the menu reads "Start Captions for <app>", the language item names the current language with a checkmark inside, no "Setup…" item; after Start, the icon gains a dot and the item reads "Stop Captions for <app>".

**Step 10: Commit**

```bash
git add Sources Tests
git commit -m "A menu that shows what is running, in sentences for people"
```

---

## Part 3 — the bar shows one sentence, and the panel keeps them all

### Task 10: The bar's two lines always belong to the same sentence

**Files:**
- Modify: `Sources/BilbyUI/CaptionModel.swift`
- Modify: `Sources/BilbyUI/CaptionBar.swift`
- Test: `Tests/BilbyUITests/CaptionModelTests.swift`

**Step 1: Write the failing tests**

```swift
import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Caption model")
@MainActor
struct CaptionModelTests {
    @Test("a finished sentence stays with its translation until the next one has a draft")
    func pairSwitchesTogether() throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for event in engine.consume(Utterance("We need to talk about the runway. And")) { model.apply(event) }
        #expect(model.pair?.source == "We need to talk about the runway.")
        #expect(model.pair?.translation == nil)

        let line = try #require(model.latest)
        for event in engine.resolve(line.id, translation: "Нам нужно поговорить о запасе денег.") { model.apply(event) }
        #expect(
            model.pair
                == CaptionModel.Pair(
                    source: "We need to talk about the runway.", translation: "Нам нужно поговорить о запасе денег.",
                    settled: true))

        model.apply(.live("And then we should"))
        #expect(model.pair?.source == "We need to talk about the runway.")

        model.apply(.draft("А потом нам следует"))
        #expect(model.pair == CaptionModel.Pair(source: "And then we should", translation: "А потом нам следует", settled: false))
    }

    @Test("a draft follows its sentence when the sentence closes")
    func draftCarriesOver() throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for event in engine.consume(Utterance("Let us begin now")) { model.apply(event) }
        model.apply(.draft("Давайте начнём"))
        for event in engine.consume(Utterance("Let us begin now. So")) { model.apply(event) }
        #expect(model.pair == CaptionModel.Pair(source: "Let us begin now.", translation: "Давайте начнём", settled: false))

        let line = try #require(model.latest)
        for event in engine.resolve(line.id, translation: "Давайте начнём.") { model.apply(event) }
        #expect(model.pair == CaptionModel.Pair(source: "Let us begin now.", translation: "Давайте начнём.", settled: true))
    }

    @Test("the first words show alone, before any translation exists")
    func firstWords() {
        let model = CaptionModel()
        model.apply(.live("Good morning everyone"))
        #expect(model.pair == CaptionModel.Pair(source: "Good morning everyone", translation: nil, settled: false))
    }

    @Test("history keeps the last five hundred sentences")
    func historyIsCapped() {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for index in 0..<505 {
            for event in engine.consume(Utterance("Sentence \(index).", isFinal: true)) { model.apply(event) }
        }
        #expect(model.lines.count == CaptionModel.historyLimit)
        #expect(model.lines.first?.source == "Sentence 5.")
        #expect(model.lines.last?.source == "Sentence 504.")
    }

    @Test("the status line clears when words arrive and when the session ends")
    func statusClears() {
        let model = CaptionModel()
        model.status = "Getting ready…"
        model.apply(.live(""))
        #expect(model.status == "Getting ready…")
        model.apply(.live("Hello"))
        #expect(model.status == nil)
        model.status = "Listening to Zoom…"
        model.clear()
        #expect(model.status == nil)
    }
}
```

**Step 2: Run to verify they fail**

Run: `swift test --filter "Caption model"`
Expected: compile errors for `Pair`, `pair`, `historyLimit`.

**Step 3: Implement the model**

Replace the body of `CaptionModel` (keeping the doc comments that still apply):

```swift
@MainActor
@Observable
public final class CaptionModel {
    /// What the bar shows: one sentence and, when there is one, its
    /// translation. Both lines always belong to the same sentence, so the
    /// reader is never shown a translation of something other than the line
    /// above it.
    public struct Pair: Equatable, Sendable {
        public let source: String
        public let translation: String?
        /// False while the translation may still change.
        public let settled: Bool
    }

    /// Enough for a two-hour meeting; more than anyone scrolls back through.
    public static let historyLimit = 500

    /// Source text, updating word by word. Sub-second.
    public private(set) var live = ""
    /// Committed lines, oldest first. A line is never rewritten.
    public private(set) var lines: [Line] = []
    /// Provisional translation of the sentence being spoken. This one may
    /// change — it is shown differently so the reader knows.
    public private(set) var draft = ""
    /// The draft the last committed sentence had when it closed, shown until
    /// its settled translation lands. Without it the bar went blank for the
    /// hundred milliseconds between the two.
    public private(set) var provisional: String?
    /// Shown while the bar has no words: what Bilby is doing instead.
    public var status: String?

    public init() {}

    public func clear() {
        live = ""
        lines = []
        draft = ""
        provisional = nil
        status = nil
    }

    public var latest: Line? { lines.last }

    /// The pair switches to the sentence being spoken only once that sentence
    /// has a draft of its own. Until then the finished one stays, so the
    /// reader gets its settled translation for at least as long as the next
    /// sentence takes to reach three words.
    public var pair: Pair? {
        if !live.isEmpty, !draft.isEmpty { return Pair(source: live, translation: draft, settled: false) }
        if let latest {
            return Pair(source: latest.source, translation: latest.translation ?? provisional, settled: latest.translation != nil)
        }
        if !live.isEmpty { return Pair(source: live, translation: nil, settled: false) }
        return nil
    }

    public func apply(_ event: CaptionEvent) {
        switch event {
        case .live(let text):
            live = text
            if !text.isEmpty { status = nil }
        case .line(let line):
            lines.append(line)
            if lines.count > Self.historyLimit { lines.removeFirst(lines.count - Self.historyLimit) }
            // The draft was of the sentence that just closed. Carry it.
            provisional = draft.isEmpty ? nil : draft
            draft = ""
        case .translated(let id, let text):
            guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[index] = lines[index].translated(text)
            provisional = nil
        case .draft(let text):
            draft = text
        }
    }
}
```

`isHidden` is unused; delete it.

**Step 4: Run the tests**

Run: `swift test --filter "Caption model"`
Expected: all pass.

**Step 5: The bar draws the pair**

Replace the `translation` computed property and the `body` in `CaptionBar.swift`:

```swift
    private var hidden: Bool { model.pair == nil && model.status == nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let pair = model.pair {
                // Same size and weight as the translation: people read both,
                // and shrinking the source turned it into decoration.
                Text(pair.source)
                    .font(Self.line)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
                if let translation = pair.translation {
                    Text(translation)
                        .font(Self.line)
                        .foregroundStyle(pair.settled ? .primary : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                }
            } else if let status = model.status {
                Label(status, systemImage: "waveform")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        }
        .opacity(hidden ? 0 : 1)
        .scaleEffect(hidden ? 0.97 : 1, anchor: .bottom)
        .blur(radius: hidden ? 6 : 0)
        .animation(.smooth(duration: 0.28), value: hidden)
        .animation(.smooth(duration: 0.18), value: model.pair)
    }
```

Delete `isEmpty`, `appeared`, and the old `translation` property.

**Step 6: Build and commit**

Run: `swift build && swift test`
Expected: green.

```bash
git add Sources/BilbyUI/CaptionModel.swift Sources/BilbyUI/CaptionBar.swift Tests/BilbyUITests/CaptionModelTests.swift
git commit -m "The bar shows one sentence and its own translation"
```

### Task 11: The history panel

**Files:**
- Create: `Sources/BilbyUI/HistoryView.swift`
- Create: `Sources/BilbyUI/HistoryPanel.swift`
- Modify: `Sources/BilbyApp/BilbyApp.swift` (mode, `present()`)
- Modify: `Sources/BilbyPreview/Preview.swift` (render the view)

**Step 1: The view**

```swift
import BilbyCore
import SwiftUI

/// Every sentence of the session, oldest at the top, for readers who want to
/// go back. The sentence being spoken sits at the bottom, dimmed, and the
/// list follows it until the reader scrolls up to read something earlier.
public struct HistoryView: View {
    private let model: CaptionModel
    @State private var atBottom = true

    public init(model: CaptionModel) { self.model = model }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.lines.isEmpty, model.live.isEmpty, let status = model.status {
                        Label(status, systemImage: "waveform")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.lines) { line in
                        row(source: line.source, translation: line.translation, settled: line.translation != nil)
                            .id(line.id)
                    }
                    if !model.live.isEmpty {
                        row(source: model.live, translation: model.draft.isEmpty ? nil : model.draft, settled: false)
                            .id("live")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(18)
                .padding(.top, 10)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
            .onChange(of: model.lines.count) { if atBottom { proxy.scrollTo("end") } }
            .onChange(of: model.live) { if atBottom { proxy.scrollTo("end") } }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button {
                        withAnimation { proxy.scrollTo("end") }
                    } label: {
                        Label("Latest", systemImage: "arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 280, minHeight: 240)
        .background(.regularMaterial)
    }

    private func row(source: String, translation: String?, settled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if let translation {
                Text(translation)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(settled ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
```

**Step 2: The panel**

```swift
import AppKit
import SwiftUI

/// The side mode's window: a column that keeps every sentence.
///
/// Unlike the bar it must take scroll events, so it is not click-through.
/// Like the bar it never takes keyboard focus from the meeting, floats over
/// full-screen calls, and stays out of screen sharing.
public final class HistoryPanel: NSPanel {
    /// Closing the panel with its button is switching back to the bar.
    public var onClose: (() -> Void)?

    public init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 280, height: 240)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView = NSHostingView(rootView: content)

        // Remembered between launches; docked to the right edge the first
        // time, the side of the screen a meeting window covers least.
        if !setFrameUsingName("HistoryPanel"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrame(
                NSRect(x: visible.maxX - 380 - 12, y: visible.minY + 12, width: 380, height: visible.height - 24),
                display: false)
        }
        setFrameAutosaveName("HistoryPanel")
    }

    public override func close() {
        super.close()
        onClose?()
    }
}
```

**Step 3: The delegate owns the mode**

In `BilbyApp.swift`:

```swift
    private(set) var showsHistory = UserDefaults.standard.bool(forKey: "showsHistory")
    @ObservationIgnored private var history: HistoryPanel?

    func setHistory(_ on: Bool) {
        showsHistory = on
        UserDefaults.standard.set(on, forKey: "showsHistory")
        present()
    }

    /// Puts whichever caption surface the mode calls for on screen, or
    /// neither. Bar and panel are modes, not layers.
    private func present() {
        guard isListening else {
            panel?.orderOut(nil)
            history?.orderOut(nil)
            return
        }
        if showsHistory {
            panel?.orderOut(nil)
            history?.orderFrontRegardless()
        } else {
            history?.orderOut(nil)
            panel?.orderFrontRegardless()
            panel?.fitContent()
        }
    }
```

In `applicationDidFinishLaunching`, after the bar panel:

```swift
        let history = HistoryPanel(content: HistoryView(model: model))
        history.onClose = { [weak self] in self?.setHistory(false) }
        self.history = history
```

In `start()`, replace `panel?.orderFrontRegardless()` with `present()`; in the event loop replace `panel?.fitContent()` with `if !showsHistory { panel?.fitContent() }`; in `finish()` replace `panel?.orderOut(nil)` with `present()` after `isListening = false`. Delete `isHidden` and `toggleCaptions()`.

**Step 4: Render it**

In `Preview.swift`, after the setup loop, add a render of the panel's content with sample data:

```swift
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            let model = CaptionModel()
            var engine = CaptionEngine()
            let script = [
                ("So let's circle back on the runway before we commit to Q3.", "Итак, давайте вернёмся к запасу денег, прежде чем брать обязательства по третьему кварталу."),
                ("Burn is up eighteen percent quarter over quarter.", "Расходы выросли на восемнадцать процентов по сравнению с прошлым кварталом."),
                ("Two senior hires are pending offer.", "Два старших специалиста ждут оффера."),
            ]
            for (source, translation) in script {
                for event in engine.consume(Utterance(source, isFinal: true)) { model.apply(event) }
                if let line = model.latest {
                    for event in engine.resolve(line.id, translation: translation) { model.apply(event) }
                }
            }
            model.apply(.live("And the bridge round term sheet"))
            model.apply(.draft("И условия промежуточного раунда"))
            let view = HistoryView(model: model).frame(width: 380, height: 520).environment(\.colorScheme, scheme)
            try save(view, to: directory.appendingPathComponent("history-\(appearance).png"))
        }
```

(`Preview` must `import BilbyCore` for `CaptionEngine` and `Utterance`; add `"BilbyCore"` to `BilbyPreview`'s dependencies in `Package.swift`.)

Run: `swift run BilbyPreview --output .build/previews && open .build/previews/history-light.png`
Expected: three finished rows, a dim live row at the bottom.

**Step 5: Run it for real**

Run: `./Scripts/make-app.sh && open ~/Applications/Bilby.app`. Start captions for a playing app, then check "Show Sentence History" in the menu. Expected: the bar disappears, a column appears at the right edge, sentences accumulate, scrolling up stops the auto-scroll and shows "Latest", the red close button returns to the bar, and the menu item's checkmark follows.

**Step 6: Commit**

```bash
git add Package.swift Sources
git commit -m "A side panel that keeps every sentence, for readers who want to go back"
```

### Task 12: Open at login, from the last setup page

**Files:**
- Create: `Sources/BilbySources/LoginItem.swift`
- Modify: `Sources/BilbyUI/SetupModel.swift`, `Sources/BilbyUI/SetupView.swift` (last page)
- Modify: `Sources/BilbyApp/BilbyApp.swift` (`showSetup`)
- Test: `Tests/BilbyUITests/SetupModelTests.swift`

**Step 1: Write the failing test**

```swift
    @Test("the login-item choice is passed on")
    func loginItem() {
        var recorded: Bool?
        let model = SetupModel(
            checkAudio: { .granted }, openSettings: {}, startListening: {},
            setOpensAtLogin: { recorded = $0 }
        )
        #expect(!model.opensAtLogin)
        model.setOpensAtLogin(true)
        #expect(model.opensAtLogin)
        #expect(recorded == true)
    }
```

**Step 2: Implement**

`SetupModel`: `public private(set) var opensAtLogin: Bool`, `private let loginItemHandler: (Bool) -> Void`, init parameters `opensAtLogin: Bool = false, setOpensAtLogin: @escaping (Bool) -> Void = { _ in }`, and:

```swift
    public func setOpensAtLogin(_ on: Bool) {
        opensAtLogin = on
        loginItemHandler(on)
    }
```

`SetupView`, `.tryIt` content, after the box:

```swift
            Toggle("Open Bilby when I log in", isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .padding(.top, 4)
```

`Sources/BilbySources/LoginItem.swift`:

```swift
import BilbyCore
import ServiceManagement

/// Registers Bilby as a login item through the system's own mechanism, so it
/// appears in System Settings → General → Login Items like any other app and
/// can be removed there.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item: FAILED — \(error)")
        }
    }
}
```

`showSetup`: pass `opensAtLogin: LoginItem.isEnabled, setOpensAtLogin: { LoginItem.set($0) }`.

**Step 3: Test, build, commit**

```bash
swift test && swift build
git add Sources Tests
git commit -m "Open at login, offered where the app is first explained"
```

### Task 13: Polish and previews

**Files:**
- Modify: `Sources/BilbyUI/SetupView.swift:20` (wordmark), `:116-121` (welcome bullets)
- Modify: `Sources/BilbyPreview/Preview.swift` (readiness scenes)
- Modify: `README.md`

**Step 1: Copy**

- Line 20: `Text("Bilby")`.
- Welcome bullets: replace the first, `Always in the menu bar, never in the Dock`, which repeats the subtitle, with `detail("Captions at the bottom of your screen", symbol: "captions.bubble")`.

**Step 2: Preview scenes for readiness**

In the setup loop of `Preview.swift`, after `try snap(model, "tryIt")`, add:

```swift
            model.update(readiness: .downloading(0.43))
            try snap(model, "tryIt-downloading")
            model.update(readiness: .failed("Speech recognition needs a one-time download. Connect to the internet and try again."))
            try snap(model, "tryIt-failed")
            model.update(readiness: .ready)
```

And a permission scene with nothing to probe: a second model with `checkAudio: { .nothingToProbe }`, advanced once, saved as `permission-nothing-playing`.

**Step 3: README**

Under Build, add the two scripts:

```
./Scripts/make-app.sh          # ~/Applications/Bilby.app, debug
./Scripts/check-app-portable.sh # the app must run with this checkout unreadable
./Scripts/release.sh           # Bilby.dmg, release build, checked
```

Under Status, replace the M1 paragraph with one line naming the design doc for this work.

**Step 4: Render, look, commit**

Run: `swift run BilbyPreview --output .build/previews` and open every `setup-*-light.png` and `history-light.png`.

```bash
git add Sources README.md
git commit -m "Copy, previews for every state, and a README that names the scripts"
```

### Task 14: Gates

Run, in this order, and fix anything red:

```bash
swift format lint --recursive Sources Tests   # report only; the repo has no config, so do not reformat wholesale
swift test
./Scripts/check-core-purity.sh
./Scripts/make-app.sh && ./Scripts/check-app-portable.sh
swift run BilbyPreview --output .build/previews
```

Then walk the app once by hand from a clean state:

```bash
defaults delete net.variant.bilby didSetUp; defaults delete net.variant.bilby targetLanguage; defaults delete net.variant.bilby showsHistory
open ~/Applications/Bilby.app
```

Expected: welcome shows the photograph; permission shows Continue; language is preselected from the system or asks for a choice; the last page shows "Getting ready…" then "Listening for your first words", and "Start using Bilby" is enabled throughout; the menu names the app and language; Show Sentence History switches views.

Finally, use superpowers:requesting-code-review against the design doc, address findings, and re-run the gates.
