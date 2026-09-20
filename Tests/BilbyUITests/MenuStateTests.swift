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
        let quietZoom = MenuState.App(id: "us.zoom", name: "Zoom", isPlaying: false)
        menu.apps = [music, quietZoom]
        menu.lastListened = quietZoom
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

    @Test("the translate item names the current language and lists only installed ones")
    func languages() {
        var menu = MenuState()
        menu.languages = [
            .init(code: "de", name: "German", isInstalled: false),
            .init(code: "ru", name: "Russian", isInstalled: true),
        ]
        menu.target = "ru"
        #expect(menu.languageTitle == "Translate to: Russian")
        #expect(menu.installedLanguages.map(\.code) == ["ru"])
        menu.target = nil
        #expect(menu.languageTitle == "Translate to")
    }
}
