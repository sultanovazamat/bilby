# Releasing Bilby

A release is a tag. Everything else — the tests, the build, the disk image,
its checksum and the release page — is `.github/workflows/release.yml`
running the same scripts you run locally.

## Cutting one

1. `main` is green in CI.
2. Tag it and push the tag:

   ```
   git tag v0.2.0
   git push origin v0.2.0
   ```

   A suffix, as in `v0.2.0-rc.1`, makes it a pre-release.
3. The workflow runs `check.sh`, builds `Bilby.dmg` at the tag's version with
   `release.sh`, and opens a **draft** release with the image, its `.sha256`,
   and notes generated from the pull requests and commits since the last tag.
4. Read the draft, edit the notes, and publish it. The README's download link,
   `releases/latest/download/Bilby.dmg`, follows the newest published release
   because the image's name never changes.

The release is named after the whole tag, but the app's version is only its
numbers: `v0.2.0-rc.1` installs as 0.2.0, because `CFBundleShortVersionString`
allows nothing else. Its build number is the workflow's run number, which is
what tells two candidates of one version apart. A local `make-app.sh` build
is `0.1.0 (1)` unless `BILBY_VERSION` and `BILBY_BUILD` say otherwise.

## Switching on signing and notarisation

Until then every image is ad-hoc signed, and people have to allow the first
launch in System Settings. With an Apple Developer Program membership:

1. Create a **Developer ID Application** certificate, and export it with its
   private key as a password-protected `.p12`.
2. In App Store Connect, under Users and Access → Integrations, create an API
   key with the Developer role. Download its `.p8`, and note its key ID and the
   issuer ID.
3. Add these repository secrets (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `MACOS_CERTIFICATE_P12` | `base64 -i certificate.p12` |
   | `MACOS_CERTIFICATE_PASSWORD` | the `.p12`'s password |
   | `MACOS_SIGNING_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
   | `KEYCHAIN_PASSWORD` | any long random string; it protects a keychain that lives for one run |
   | `NOTARY_KEY_P8` | `base64 -i AuthKey_XXXXXXXXXX.p8` |
   | `NOTARY_KEY_ID` | the key ID |
   | `NOTARY_ISSUER_ID` | the issuer ID |

4. The next tag is signed with the hardened runtime, notarised, stapled, and
   verified by `release.sh` before it is uploaded. Then take the "Open Anyway"
   step out of the README.

This path follows GitHub's procedure for certificates on hosted runners and
Apple's for `notarytool`, but it has not run yet: the first signed release is
its test. Watch that run.
