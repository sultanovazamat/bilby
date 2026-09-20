import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Menu")
struct MenuStateTests {
    let zoom = MenuState.App(id: "us.zoom", name: "Zoom", isPlaying: true)
    let music = MenuState.App(id: "com.apple.Music", name: "Music", isPlaying: false)

    @Test("nothing is checked until captions are running")
    func idle() {
        var menu = MenuState()
        menu.apps = [music, zoom]
        #expect(menu.checkedApp == nil)
        #expect(menu.statusLine == nil)
        #expect(menu.apps.map(\.name) == ["Music", "Zoom"])
    }

    @Test("the app being captioned is the one that is checked")
    func running() {
        var menu = MenuState()
        menu.apps = [music, zoom]
        menu.listening = zoom
        menu.readiness = .ready
        menu.pipeline = .flowing(lines: 4)
        #expect(menu.checkedApp == "us.zoom")
        #expect(menu.statusLine == nil)
        menu.pipeline = .noAudio
        #expect(menu.statusLine == "No sound from Zoom yet. Is it muted?")
        menu.readiness = .downloading(0.4)
        #expect(menu.statusLine == "Downloading speech recognition, 40%")
    }

    @Test("the top line always says the state, running or not")
    func header() {
        var menu = MenuState()
        menu.apps = [zoom]
        menu.languages = [.init(code: "ru", name: "Russian", isInstalled: true)]
        menu.target = "ru"
        #expect(menu.header == "Not listening")
        menu.listening = zoom
        #expect(menu.header == "Zoom → Russian")
        menu.target = nil
        #expect(menu.header == "Zoom")
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
