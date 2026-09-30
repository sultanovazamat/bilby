# Open Source and GitHub Releases Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Publish Bilby as an MIT-licensed repository at `github.com/sultanovazamat/bilby`, with CI on every change and a disk image attached to a GitHub Release for every tag.

**Architecture:** Nothing about how the app is built changes: `release.sh` already makes a checked disk image, and signs and notarises it when given an identity. The work is around it: licences and notices, a README and community files, two workflows that run the existing scripts on a `macos-26` runner, and a history rewritten so that only a personal email is public.

**Tech Stack:** GitHub Actions (`macos-26`), `gh`, `git-filter-repo`, `gitleaks`, `actionlint`, `dmgbuild` (already used by `release.sh`).

Decided with the owner on 2026-09-30:
- The repository is personal (`sultanovazamat`), not Variant's.
- Licence: MIT.
- Releases are ad-hoc signed for now. Signing and notarisation switch on when the secrets are added.
- History: the Variant email is rewritten to the personal one; commits and messages are kept.
- Name: `bilby`.

Conventions for every task:
- The gate is `./Scripts/check.sh`; workflows are linted with `actionlint`.
- Work happens on `open-source`; `main` fast-forwards to it when Phase 1 is done.
- Anything outward-facing waits for the owner: the repository goes public, and a release is published, only when they say so.

---

## Phase 1 — the repository, prepared locally

1. **Variant leaves the code.** The bundle identifier becomes `io.github.sultanovazamat.bilby` in `Scripts/make-app.sh`, the log queue label in `Sources/BilbyCore/Log.swift`, and the aggregate device UID and tap queue label in `Sources/BilbySources/SystemAudioTap.swift`. Plan documents keep their mentions; they record what was done at the time.
2. **Versions.** `make-app.sh` writes `BILBY_VERSION` (default `0.1.0`) to `CFBundleShortVersionString` and `BILBY_BUILD` (default `1`) to `CFBundleVersion`.
3. **Licences travel with the app.**
   - `LICENSE` is MIT, from GitHub's template.
   - `THIRD_PARTY_NOTICES.md` holds FluidAudio's Apache-2.0 licence, the fastcluster and VBx licences it carries for code it ported, and the CC-BY-4.0 attribution for the Parakeet Unified model.
   - `make-app.sh` copies the notices into `Contents/Resources`, and `check-app-portable.sh` fails without them.
4. **README** with the icon, badges, a permanent download link (`releases/latest/download/Bilby.dmg`), and a hero image rendered by `BilbyPreview`. It covers privacy, installation (including the "Open Anyway" steps while releases are unsigned), how it works, building from source, and credits.
5. **Community files:**
   - `CONTRIBUTING.md`;
   - `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1);
   - `SECURITY.md` (security boundaries and supported versions);
   - issue forms for bugs and features, and a pull request template.
6. **Automation:**
   - `.github/workflows/ci.yml`: `check.sh` on every push to `main` and on every pull request.
   - `.github/workflows/release.yml`, on a `v*` tag: run `check.sh`, then `release.sh` at the tag's version, then create a SHA-256 checksum and a draft release.
   - Signing in `release.yml` follows GitHub's temporary-keychain procedure and uses `notarytool` with an App Store Connect API key. It is dormant until the secrets exist.
   - `.github/dependabot.yml` for GitHub Actions only.
   - `docs/releasing.md`: how to cut a release, and which secrets switch signing on.
7. **Small fixes.**
   - `release.sh` says what Gatekeeper actually does since macOS 15, not "warn once".
   - `.gitignore` gains `Bilby.iconset`.
8. **Cleanup.** `Spike/` (a finished experiment whose findings stay in `docs/plans`) and the unused `menu-open.png` leave the tree.
9. **Owner:** retake `menu-bar.png` and `menu-sources.png` from the installed build before the first tag.

## Phase 2 — the history, rewritten in a scratch clone

1. `git clone --no-local` this repository.
2. Run `git filter-repo --mailmap` to map the Variant email to the personal one, for author and committer.
3. Verify: no Variant email in any author or committer field, and `gitleaks git --redact` finds nothing.
4. Point the four commit-hash references in `docs/plans` at their rewritten commits, using `.git/filter-repo/commit-map`.

## Phase 3 — publishing, staged

1. Create the repository private and push `main`. CI must pass there.
2. Tag `v0.1.0-rc.1` and check the draft pre-release's disk image. Then delete the release and the tag.
3. **Owner says go public.** Then set visibility, description and topics. The owner uploads the social preview; GitHub has no API for it.
4. Tag `v0.1.0`. **The owner reads the draft and publishes it.**

## Acceptance criteria

1. The repository is public; GitHub detects the MIT licence.
2. `git log --all --format='%ae %ce' | grep -c variant.net` is 0, and `gitleaks` finds nothing in any commit.
3. `Sources/` and `Scripts/` contain no `net.variant`.
4. CI passes on `main`, and GitHub's community profile is complete.
5. Tag `v0.1.0` produces `Bilby.dmg` and its checksum. The app inside reports 0.1.0, carries the notices, and opens by the README's steps.
6. The README's download link fetches the latest disk image.
