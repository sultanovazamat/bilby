# Contributing to Bilby

Thank you for helping. This page is what you need to change Bilby without
tripping over the few rules that keep it working.

## Setting up

You need a Mac with Apple silicon, macOS 26, and Xcode 26. Then:

```
./Scripts/check.sh
```

That runs the tests, checks that the core stays pure, builds in release, and
launches the built app with this checkout unreadable. A pull request needs it
green; CI runs the same script.

`./Scripts/make-app.sh` installs a debug build at `~/Applications/Bilby.app`.
It is not built into `~/Desktop` on purpose: an app living there triggers a
Desktop-access prompt just by reading its own resources.

## How the code is laid out

| Target | What lives there |
|---|---|
| `BilbyCore` | The product's logic — sentences, timing, the transcript — in pure Swift. It must never import a platform framework; `Scripts/check-core-purity.sh` fails if it does. |
| `BilbySources` | The edges: the Core Audio tap, FluidAudio's recogniser, Apple's Translation. |
| `BilbyUI` | SwiftUI and AppKit views, and the models behind them. |
| `BilbyApp` | The menu bar app that wires the rest together. |
| `BilbyPreview` | Renders every setup scene, the caption bar, and the app icon, without launching the app. |

Each edge the core depends on is a protocol with a fake, so the core is
tested with strings: no audio, no network, no Apple Intelligence. New logic
belongs in the core with tests beside it.

## Rules that were learned the hard way

- **Nothing a person said goes in the log.** Not a sentence, not a
  translation, not a fragment. Lengths and counts are enough to find a stall.
  The log once held whole meetings in `/tmp`.
- **No `Bundle.module` in BilbyUI.** SwiftPM's accessor finds resources only
  on the Mac that built the app, and crashes on every other one. Use
  `UIResources`; `Scripts/check-app-portable.sh` catches a regression.
- **The release build is the one that counts.** Strict concurrency finds
  races under whole-module optimisation that the debug build accepts, which
  is why `check.sh` builds release.

## Changing what people see

Render the scenes before and after, and put both in the pull request:

```
swift run BilbyPreview --output .build/previews
```

The icon is a path, `BilbyMark`, not an image. After changing it, regenerate
the app icon:

```
swift run BilbyPreview --icon
iconutil -c icns Bilby.iconset -o Resources/Bilby.icns
rm -rf Bilby.iconset
```

## Writing it down

Comments in this codebase say why, not what: the reason a line exists, the
alternative that was tried, the bug it prevents. Commit messages do the same —
a plain sentence as the title, and a body explaining why the change is
right. Larger changes start as a short design in `docs/plans`.

## Conduct

Everyone taking part agrees to the [Code of Conduct](CODE_OF_CONDUCT.md).
[SECURITY.md](SECURITY.md) describes the app's security boundaries and supported versions.
