import Synchronization
import Testing

@testable import BilbyUI

@Suite("Onboarding")
@MainActor
struct SetupModelTests {
    @Test("welcome and transition do not probe audio before the explanation is visible")
    func explainsBeforeChecking() {
        let checks = Mutex(0)
        let model = SetupModel(
            checkAudio: {
                checks.withLock { $0 += 1 }
                return false
            },
            openSettings: {}, startListening: {}
        )
        #expect(checks.withLock { $0 } == 0)
        model.advance()
        #expect(model.step == .permission)
        #expect(checks.withLock { $0 } == 0)
        model.stopWatching()
    }

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

    @Test("permission cannot be bypassed into a listening session")
    func deniedPermissionBlocksAdvance() {
        var starts = 0
        let model = SetupModel(
            checkAudio: { false }, openSettings: {}, startListening: { starts += 1 }
        )
        model.advance()
        #expect(!model.canContinue)
        model.advance()
        model.advance()
        #expect(model.step == .permission)
        #expect(starts == 0)
        model.stopWatching()
    }

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

    @Test("permission granted later in Settings also advances automatically")
    func newGrantAdvances() async {
        let checks = Mutex(0)
        let model = SetupModel(
            checkAudio: {
                checks.withLock {
                    $0 += 1
                    return $0 > 1
                }
            },
            openSettings: {}, startListening: {}
        )
        model.advance()
        await model.watchPermission()
        #expect(checks.withLock { $0 } == 2)
        #expect(model.step == .language)
    }

    @Test("a closed permission page cannot prompt or advance")
    func closedPermissionPage() async {
        let checks = Mutex(0)
        let model = SetupModel(
            checkAudio: {
                checks.withLock { $0 += 1 }
                return true
            },
            openSettings: {}, startListening: {}
        )
        model.advance()
        model.stopWatching()
        await model.watchPermission()
        model.requestAudioAccess()
        #expect(checks.withLock { $0 } == 0)
        #expect(model.step == .permission)
    }

    @Test("an unavailable language starts a preparation request and blocks listening")
    func downloadIsRequired() async throws {
        var chosen: String?
        var starts = 0
        let model = makeModel(selectTarget: { chosen = $0 }, startListening: { starts += 1 })
        await reachLanguages(model)
        #expect(model.selectedLanguageCode == "ru")
        #expect(!model.canContinue)
        model.advance()
        #expect(starts == 0)
        model.prepareLanguage()
        let request = try #require(model.preparation)
        #expect(request.code == "ru")
        #expect(!model.canContinue)
        model.completePreparation(request, error: nil)
        #expect(model.canContinue)
        model.advance()
        #expect(model.step == .tryIt)
        #expect(chosen == "ru")
        #expect(starts == 1)
        #expect(model.canContinue)
        model.show("Hello", "Привет")
        #expect(model.caption?.translation == "Привет")
    }

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

    @Test("an installed language continues without a download")
    func installedLanguage() async {
        let model = makeModel()
        await reachLanguages(model)
        model.selectLanguage("fr")
        #expect(model.canContinue)
        model.prepareLanguage()
        #expect(model.preparation == nil)
        model.advance()
        #expect(model.step == .tryIt)
    }

    @Test("failed downloads can be retried and stale completions are ignored")
    func retryDownload() async throws {
        let model = makeModel()
        await reachLanguages(model)
        model.prepareLanguage()
        let first = try #require(model.preparation)
        model.prepareLanguage()
        #expect(model.preparation == first)
        model.completePreparation(first, error: "Download cancelled. Try again.")
        #expect(model.languageError != nil)
        #expect(!model.canContinue)
        model.prepareLanguage()
        let retry = try #require(model.preparation)
        #expect(retry != first)
        model.completePreparation(first, error: nil)
        #expect(!model.canContinue)
        model.completePreparation(retry, error: nil)
        #expect(model.canContinue)
        #expect(model.languageError == nil)
    }

    @Test("changing languages cancels preparation without accepting its late result")
    func changeDuringDownload() async throws {
        let model = makeModel()
        await reachLanguages(model)
        model.prepareLanguage()
        let request = try #require(model.preparation)
        model.selectLanguage("fr")
        model.completePreparation(request, error: nil)
        model.selectLanguage("ru")
        #expect(!model.canContinue)
        #expect(model.preparation == nil)
    }

    @Test("cancelling a download leaves the same language retryable")
    func cancelDownload() async throws {
        let model = makeModel()
        await reachLanguages(model)
        model.prepareLanguage()
        let cancelled = try #require(model.preparation)
        model.cancelPreparation()
        model.completePreparation(cancelled, error: nil)
        #expect(!model.canContinue)
        model.prepareLanguage()
        let retry = try #require(model.preparation)
        #expect(retry.code == cancelled.code)
        #expect(retry.id != cancelled.id)
    }

    @Test("closing setup cancels pending work and ignores late callbacks")
    func closeDuringDownload() async throws {
        let model = makeModel()
        await reachLanguages(model)
        model.prepareLanguage()
        let request = try #require(model.preparation)
        model.stopWatching()
        model.completePreparation(request, error: nil)
        model.advance()
        #expect(model.preparation == nil)
        #expect(model.step == .language)
        #expect(!model.canContinue)
    }

    @Test("an empty language list offers retry instead of proceeding")
    func emptyLanguages() async {
        let model = SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: {}, loadLanguages: { [] }
        )
        await reachLanguages(model)
        #expect(!model.canContinue)
        #expect(model.languageError != nil)
        #expect(!model.isLoadingLanguages)
    }

    @Test("a repeated page appearance preserves download errors and the loaded choices")
    func repeatedLanguageAppearance() async throws {
        let model = makeModel()
        await reachLanguages(model)
        model.prepareLanguage()
        let request = try #require(model.preparation)
        model.completePreparation(request, error: "Download failed. Try again.")
        await model.loadLanguages()
        #expect(model.languageError == "Download failed. Try again.")
        #expect(model.selectedLanguageCode == "ru")
        #expect(!model.canContinue)
    }

    private func makeModel(
        selectTarget: @escaping (String) -> Void = { _ in },
        startListening: @escaping () -> Void = {}
    ) -> SetupModel {
        SetupModel(
            checkAudio: { true }, openSettings: {}, startListening: startListening,
            loadLanguages: {
                [
                    .init(code: "ru", name: "Russian", isInstalled: false),
                    .init(code: "fr", name: "French", isInstalled: true),
                ]
            }, selectTarget: selectTarget
        )
    }

    /// Permission granted before the page opened is confirmed, not skipped —
    /// that page is where Bilby says it lives in the menu bar — so reaching
    /// the language step takes an explicit step forward.
    private func reachLanguages(_ model: SetupModel) async {
        model.advance()
        model.requestAudioAccess()
        model.advance()
        await model.loadLanguages()
    }
}
