# Changelog

All notable changes to Rescripto are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

## [1.1.2] - 2026-08-14

### Fixed

- SnackBar feedback (validation errors, engine errors, save confirmations)
  could silently fail to appear across most of the app. Root cause: several
  screens live inside their own nested `Scaffold` under the bottom
  navigation bar's outer `Scaffold`, and calling
  `ScaffoldMessenger.of(context)` from a screen's own `State` resolved
  ambiguously depending on where in that nesting the call sat. Every
  SnackBar in the app now goes through one explicit, app-wide messenger key
  instead.
- The Rewrite screen's processing-target indicator and "disabled in Privacy
  settings" banner could go stale after a Privacy toggle was changed on a
  different screen, until an unrelated action refreshed it. It now updates
  immediately.
- A cloud rewrite blocked by the network kill switch or the Cloud rewriting
  toggle no longer disappears from the Network log — it's recorded the same
  way every other blocked or completed request is.

## [1.1.1] - 2026-08-12

### Fixed

- Rewrite quality, cloud request routing, and voice engine selection issues
  found during hardening.

## [1.1.0] - 2026-08-12

### Added

- Android system integration: share text into Rescripto from any app via
  `PROCESS_TEXT` / `ACTION_SEND`, and a Quick Settings tile.
- WebDAV/Nextcloud sync, with per-section selection of what syncs.
- Scheduled local backups.
- Encrypted backup export, and import/restore with a preview step before
  anything is applied.
- Pro generation controls: per-tone top-P, top-K, repeat penalty, max
  output tokens, and stop sequences.
- Multi-step workflows — chain rewrite steps into one saved pipeline.
- The audience editor, and the tone preset studio.
- Simple/Pro editor modes.

## Earlier history

Everything before 1.1.0 — the initial local rewrite engine, cloud provider
adapters, the network guard and privacy controls, onboarding, and the core
app architecture — predates this changelog. See `git log` or the
[commit history](https://github.com/Gr33nOps/Rescripto/commits/main) for
the full record.

[1.1.2]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.1.2
[1.1.1]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.1.1
[1.1.0]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.1.0
