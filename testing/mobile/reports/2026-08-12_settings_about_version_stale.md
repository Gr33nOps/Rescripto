ID:               ABOUT-VERSION-001
Severity:         Low
Area:             Settings > About
Feature:          "Rescripto vX.Y.Z" string shown in Settings, and the
                   `app_version` field stamped into every exported backup
                   bundle
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from HEAD `2365240`
                   ("Bump version to 1.1.1 for release") during this QA
                   pass
Preconditions:    None — always visible on Settings > About (scroll to the
                   bottom).
Steps to reproduce:
  1. Open Settings, scroll to the "About" section.
Expected behavior:
  Shows "Rescripto v1.1.1" (matching pubspec.yaml's `version: 1.1.1+6`,
  the version this exact build was cut from).
Actual behavior:
  Shows "Rescripto v1.1.0" — one release behind.
Reproducibility: Always
Screenshot/video: testing/mobile/screenshots/settings_about_version_20260812_165641.png
Relevant logs:    N/A — not a runtime error, a stale constant.
Suspected cause:  `lib/core/constants.dart:22` hand-maintains
                   `AppConstants.versionName = '1.1.0'` with a comment
                   directly above it saying "Keep in step with `version:`
                   in pubspec.yaml". Commit `2365240` ("Bump version to
                   1.1.1 for release") bumped `pubspec.yaml`'s `version:`
                   to `1.1.1+6` (`git show --stat 2365240` touches only
                   `pubspec.yaml`, 1 file changed) but did not update this
                   constant, so both the About screen
                   (`lib/screens/settings_screen.dart:323`,
                   `'${AppConstants.appName} v${AppConstants.versionName}'`)
                   and `BackupService`'s `appVersion` field
                   (`lib/services/backup/backup_service.dart:77`, which
                   ends up in every exported backup bundle's metadata —
                   see `lib/models/backup_bundle.dart`) are one version
                   behind. Not a functional bug (nothing branches on this
                   string today), but it does mean backup bundles exported
                   from a 1.1.1 build are mislabeled as 1.1.0, which could
                   confuse debugging a future restore issue.

Regression test added: `test/constants_test.dart` — parses `version:` out
of `pubspec.yaml` and asserts `AppConstants.versionName` matches. Currently
**failing** against the working tree (expected '1.1.1', actual '1.1.0'),
which is the correct/intended state until the constant is fixed; run
`flutter test test/constants_test.dart` to reproduce. This is a permanent
regression test per the QA plan's guidance for deterministic bugs — it
will catch the same mistake on the next version bump. No production code
was changed to make this pass, per the "don't change application behavior
to make a test pass" rule — the constant itself is left as found.
