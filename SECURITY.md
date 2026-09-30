# Security

Bilby processes private audio and captions on the Mac. Local processing reduces
network exposure, but does not remove risks from downloads, other local software,
or screen sharing.

## Reporting

This repository is currently private. Collaborators can report vulnerabilities
in [a repository issue](https://github.com/sultanovazamat/bilby/issues/new).
These issues are visible to everyone with repository access, not just the owner.
Confirm that GitHub still labels the repository **Private** before posting
sensitive details. Describe the impact and provide a reproduction using synthetic
content; do not attach private conversations or credentials.

If you received a build without repository access, contact the maintainer through
the person or private channel that provided your copy. Do not post vulnerability
details in public issues. Before making this repository public, the maintainer
must enable GitHub's private vulnerability reporting and update these instructions
to the working private-report form.

## Security boundaries

- Audio capture uses the selected app's output and macOS's system-audio permission.
  Bilby does not use the microphone or upload audio, captions or translations.
- Initial setup needs the network. Speech models come from a pinned Hugging Face
  revision and must match the file sizes and SHA-256 hashes bundled with the app.
  Apple manages translation-language downloads. No model-tree response controls
  Bilby's filesystem paths. Missing model files can require another download.
- Conversation text stays in application memory. The visible and core caption
  history are bounded; recognizer sessions are periodically reset and cleared
  before reuse. Caption queues have fixed limits; if a downstream stage stalls,
  capture stops and the menu reports the overload rather than accumulating an
  unlimited backlog. Clearing Swift values does not promise cryptographic erasure
  from RAM, swap, operating-system diagnostics or another process with debugging access.
- The diagnostic log uses owner-only permissions, rejects symlink and nonregular
  targets, and records counts, timings and error identifiers rather than spoken
  text or framework error descriptions. File permissions isolate other user
  accounts, not arbitrary software running as the same user.
- Captions appear in screenshots, screen recordings and screen sharing. Bilby
  does not try to hide its windows from capture.
- App builds enable Hardened Runtime and reject unsafe runtime exceptions.
  The application is not App Sandbox-contained. An unrestricted malicious
  process already running as your user remains outside Bilby's isolation guarantees.

Report any violation of these boundaries, unexpected file access, unsafe model
handling, or a way to run untrusted code inside Bilby.

## Builds and supported versions

Fixes target the latest source on `main` and the latest published release.
Download disk images only from this repository's Releases page and verify the
accompanying `.sha256` file. A checksum detects altered bytes but does not
independently authenticate the publisher if both files were replaced.

Until Developer ID signing and notarization are configured, builds are ad-hoc
signed with Hardened Runtime and require **Open Anyway** on first launch. Release
notes must state their signing/notarization status. Hardened Runtime and a valid
ad-hoc signature do not establish the developer's identity.
