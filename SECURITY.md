# Security

Bilby hears everything a chosen app plays, so a flaw in it can expose a
private conversation. Please report one privately, not in a public issue.

## Reporting

Use [GitHub's private vulnerability reporting](https://github.com/sultanovazamat/bilby/security/advisories/new).
The report is visible only to the maintainer. Say what an attacker could
read, change or run, and how to reproduce it.

## What counts

Anything that breaks one of the promises in the README, for example:

- audio, captions or translations reaching the network, another app, or
  another user on the same Mac;
- anything written to disk containing what was said — the log must hold
  lengths and counts only;
- Bilby hearing an app other than the one chosen, or using the microphone;
- a way to make Bilby run code it did not ship with.

## Supported versions

Only the latest release is fixed. Releases are ad-hoc signed and not yet
notarised, so check that a download came from this repository's Releases
page, and compare it with the `.sha256` file beside it.
