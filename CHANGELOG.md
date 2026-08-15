# Changelog

All notable changes to Rescripto are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

## [1.2.6] - 2026-08-15

### Changed

- Reworked in-app wording to be shorter, clearer, and more helpful throughout
  setup, rewriting, models, settings, privacy, providers, backup, and sync.
- Improved error messages so they explain what happened and what to try next.
- Simplified the rewrite result screen and removed technical generation
  statistics that were not useful during everyday writing.
- Updated the README and privacy descriptions to match the voice and release
  options that are actually available.

### Compatibility

- Existing voice models, rewrite models, settings, history, and backups remain
  compatible. No download or data migration is required.

## [1.2.5] - 2026-08-15

### Fixed

- Fixed recorded voice clips failing at transcription on some Samsung phones.
- Rescripto now reads its own 16 kHz mono WAV recordings directly before
  falling back to the general audio decoder.
- Existing voice models, rewrite models, settings, and history are preserved.

## [1.2.4] - 2026-08-15

### Fixed

- Fixed the release-only voice crash caused by Android's code optimizer
  renaming the Whisper progress callback used by native code.
- Voice startup now frees the loaded rewrite model first, keeping native
  memory use lower on phones such as the Galaxy A06.
- Whisper now starts on its compatible CPU path and returns initialization
  failures to the app instead of allowing a native exception to close it.

## [1.2.3] - 2026-08-15

### Fixed

- Fixed the Whisper JNI method names used when opening a downloaded voice
  model. This resolves the voice initialization failure after the native
  library preflight succeeds.
- Added a regression check for the JNI package-name encoding.

## [1.2.2] - 2026-08-15

### Fixed

- Made on-device voice loading use one explicit Android native-library path,
  so the voice preflight and model initialization do not load different copies
  of the same library.
- Voice errors now identify the failed loading stage and retain Android's
  sanitized linker details instead of always reporting a generic failure.

## [1.2.1] - 2026-08-15

### Fixed

- Made on-device text and voice models more reliable on Android 7.0+ 64-bit
  ARM phones. The app now loads a compatible CPU backend from the app's native
  library directory and uses newer CPU features only when the phone supports
  them.
- Replaced misleading model and voice compatibility messages with specific
  native-load and backend errors, including a retry path for voice input.
- Prevented long rewrite prompts from crashing native generation by filling
  the model context in safe batches.

### Changed

- Native libraries are extracted from the APK so Android can load the chosen
  CPU backend reliably on Samsung, Redmi, and similar devices.

## [1.2.0] - 2026-08-15

### Changed

- Refined the Android interface across rewriting, history, models, settings,
  privacy, providers, backup, and WebDAV flows.

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
  toggle no longer disappears from the Network log. It's recorded the same
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
- Multi-step workflows, chaining rewrite steps into one saved pipeline.
- The audience editor, and the tone preset studio.
- Simple/Pro editor modes.

## Earlier history

Everything before 1.1.0 (the initial local rewrite engine, cloud provider
adapters, the network guard and privacy controls, onboarding, and the core
app architecture) predates this changelog. See `git log` or the
[commit history](https://github.com/Gr33nOps/Rescripto/commits/main) for
the full record.

[1.1.2]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.1.2
[1.2.6]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.6
[1.2.5]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.5
[1.2.4]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.4
[1.2.3]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.3
[1.2.2]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.2
[1.2.1]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.1
[1.2.0]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.2.0
[1.1.1]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.1.1
[1.1.0]: https://github.com/Gr33nOps/Rescripto/releases/tag/v1.1.0
