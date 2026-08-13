ID:               SNACKBAR-FEEDBACK-MISSING-001
Severity:         High
Area:             App-wide (SnackBar/ScaffoldMessenger feedback)
Feature:          Every `ScaffoldMessenger.of(context).showSnackBar(...)` call
                   reached during this pass — confirmed on the Rewrite screen
                   (empty-input validation, local-engine error) and the
                   WebDAV sync screen ("Server password saved.")
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from HEAD `2365240`
                   ("Bump version to 1.1.1 for release"), rebuilt during this
                   QA pass with the PROVIDER-001 fix applied
                   (`lib/state/app_providers.dart`:
                   `Provider<ModelManager>` -> `ChangeNotifierProvider<ModelManager>`)
Preconditions:    None — reproduces from a cold app launch, first interaction.
Steps to reproduce (any one of these, each independently sufficient):
  1. Rewrite screen, leave "Text to rewrite" empty, tap "Rewrite".
     Expected: SnackBar "Nothing to rewrite yet." Actual: nothing.
  2. Processing mode = Local, a model installed (Gemma 3 1B), tap "Rewrite"
     with any input. On this x86_64 emulator the model load itself fails
     (see suspected cause) with a typed `ModelLoadFailedException`, which
     `_rewrite()` explicitly catches and is supposed to surface via
     `ScaffoldMessenger...showSnackBar(SnackBar(content:
     Text(describeEngineError(e))))`. Actual: nothing — no SnackBar, no
     other visible change.
  3. Settings > Backup > WebDAV sync > "Set server password" > enter a
     password > Save. Expected: SnackBar "Server password saved." (the
     underlying save itself does work — confirmed separately, e.g. a
     follow-up sync succeeds with the new password). Actual: nothing.
Expected behavior:
  Each of the above shows its SnackBar for the usual ~4 seconds.
Actual behavior:
  No SnackBar appears for any of them, in any combination tried:
  - Reproduced on a long-lived app session (after ~1.5 hours of QA
    activity across many screens).
  - Reproduced again immediately after `adb shell am force-stop` +
    relaunch (brand-new process, first interaction after launch) — rules
    out session/memory buildup as the cause.
  - Reproduced with the device screen confirmed `Awake`
    (`dumpsys power` → `mWakefulness=Awake`) at the time of the failed
    attempts — rules out a screen-asleep/animation-frozen explanation.
  - Not a screenshot-timing artifact: other transient Flutter overlays
    (AlertDialogs, the password-entry dialog, the "Choose a model" bottom
    sheet, the system file picker) were all captured cleanly by the same
    screenshot method throughout this same session — only bare
    `SnackBar`s are affected.
  For contrast/scope: this is specifically about the *SnackBar* feedback
  mechanism. Other feedback mechanisms on the same screens work
  correctly and were verified independently this pass — the WebDAV
  screen's persistent "Last pushed: <timestamp>" status line updates
  correctly, `ModelNotInstalledException` correctly navigates to the
  Models tab (a different code path, no SnackBar involved), and the
  underlying actions behind each SnackBar-less call above (validation,
  the password save, the engine error) all take effect correctly — only
  the toast-style confirmation/error text never renders.
Reproducibility: Always, across 3 distinct trigger call sites, 2 distinct
  screens, both a long-lived and a freshly-launched app process.
Screenshot/video:
  testing/mobile/screenshots/snackbar_missing_fresh_process_empty_input_20260813_065220.png
  (fresh process, empty-input tap, no SnackBar)
  testing/mobile/screenshots/snackbar_missing_local_model_error_20260813_065220.png
  (local-engine error path, no SnackBar)
  testing/mobile/screenshots/snackbar_missing_webdav_password_saved_20260813_065220.png
  (WebDAV password-save path, no SnackBar)
Relevant logs:    testing/mobile/logs/logcat_20260813_030027.txt and the
  live-tail capture referenced in this pass confirm the local-engine
  error is genuinely thrown and caught (see
  `[FlutterLlama] Error loading model: INIT_FAILED ...` /
  `E/FlutterLlamaBridge` lines) — the failure to display is downstream of
  a correctly-thrown, correctly-typed exception, not a missing catch
  clause. No crash, no "Unhandled Exception" logcat line accompanies any
  of the three repros — unlike PROVIDER-001 and
  WEBDAV-SYNC-SILENT-FAIL-001, this is not an uncaught-exception pattern;
  the app-level `try`/`catch` blocks that are supposed to react to the
  failure are known (from code review) to run, and the call *into*
  `ScaffoldMessenger.showSnackBar` itself is what appears to have no
  effect.
Suspected cause:  Not confirmed from logs alone (no exception is thrown
  by the `showSnackBar` call, so nothing surfaces in logcat about it).
  Code review of the three call sites
  (`lib/screens/rewrite_screen.dart:250-265` inside `_rewrite()`,
  `lib/screens/backup/sync_screen.dart`'s save-password handler) shows a
  standard `if (!mounted) return; ScaffoldMessenger.of(context)
  .showSnackBar(...)` pattern with nothing unusual — the root
  `MaterialApp` in `lib/app.dart` is also a completely standard
  `MaterialApp(... home: ...)` with no custom `scaffoldMessengerKey` or
  nested `Navigator` that would obviously orphan the messenger context.
  Given this reproduces identically across unrelated screens and a fresh
  process, a plausible next debugging step is checking whether something
  in the widget tree between `MaterialApp` and these screens (e.g. the
  bottom-nav `IndexedStack` in `HomeShell`, or a `Semantics`/overlay
  wrapper recently added around action buttons per this session's
  in-progress accessibility-identifier changes) is intercepting or
  discarding the `Overlay` insertion `SnackBar` relies on. Not something
  this QA pass could isolate further without adding temporary debug
  instrumentation to production code, which is out of scope for a QA
  pass per the "don't change application behavior" rule.

Re-verification (2026-08-13, later same-day QA pass, build 2365240,
  Appium-driven, real device interaction — not source review):
  All 3 original repro steps were re-run precisely and **all 3 still
  reproduce** — no SnackBar for empty-input, no SnackBar for the local
  model INIT_FAILED error (freshly confirmed via logcat that the error is
  still genuinely thrown), no SnackBar for WebDAV "Server password saved."
  Screenshots: testing/mobile/screenshots/49_reverify_empty_input_no_snackbar_20260813.png,
  50_reverify_local_model_error_no_snackbar_20260813.png,
  51_reverify_webdav_password_saved_no_snackbar_20260813.png.

  New finding this pass: the SnackBar mechanism is **not** universally
  broken. A 4th, previously-untested call site — the same
  `ScaffoldMessenger.of(context).showSnackBar(...)` at
  rewrite_screen.dart:263-265, reached via the `EngineException` branch
  when `TargetRouter` blocks a Cloud attempt pre-flight (Privacy toggle
  off, or the kill switch) — **does** show its SnackBar reliably (3/3
  attempts), both the exact "Nothing to rewrite yet."-style validation
  message's sibling and `describeEngineError`'s "That processing target
  isn't available right now..." text. Screenshot:
  testing/mobile/screenshots/52_counterexample_not_ready_snackbar_WORKS_20260813.png.
  This rules out "ScaffoldMessenger/Overlay wiring is broken app-wide" as
  the root cause — the same call, same screen, same catch-block shape
  works from one throw site and not from others. Code comparison of the
  throw sites (state/rewrite_controller.dart) shows the working site
  (`EngineNotAvailableException`, line ~235-238) and one of the still-
  broken sites (`ModelLoadFailedException` surfaced via `_run()`'s
  `on EngineException catch` at line ~397-406) both call
  `notifyListeners()` before the exception reaches the screen, so that is
  not the differentiator either — ruled out by this pass, still unexplained.
  The working site is a synchronous, no-`await`-gap throw (routing is
  computed and blocked before any engine call); the still-broken model-load
  site crosses a real `await engine.prepare(target)` gap first. Worth a
  future debugging session comparing sync-throw vs. async-gap-then-throw
  SnackBar delivery specifically, since that is the one structural
  difference this pass could isolate. Severity unchanged at High — this is
  still a real, majority-reproducing gap in user-facing error feedback,
  just not a 100%-of-all-SnackBars failure as originally scoped.

Fourth reproduction (2026-08-13, offline testing pass): with `svc wifi
  disable` + `svc data disable` (device fully offline) and Processing mode =
  Cloud, tapping Rewrite on a configured Groq provider produces **no visible
  feedback whatsoever** — no snackbar, no banner, no error text anywhere on
  screen; the Rewrite button simply returns to its idle state as if nothing
  happened. This is not a cosmetic gap: `Settings > Privacy & network >
  Network log` confirms the request was genuinely attempted and genuinely
  failed (`POST api.groq.com/openai/v1/chat/completions · Cloud rewrite via
  Groq · Failed · 201ms`), so a real user losing signal mid-session would see
  their tapped Rewrite silently do nothing, with zero indication of what
  went wrong or that anything went wrong at all. This goes through the same
  `on EngineException catch (e)` block at rewrite_screen.dart:256-265 as the
  local-model-error repro, reinforcing that whatever suppresses the SnackBar
  is not specific to the local/on-device path — it also reproduces for a
  genuine network-layer failure on the Cloud path, arguably the single most
  common real-world failure mode this app has. Screenshots:
  testing/mobile/screenshots/53_offline_rewrite_no_feedback_20260813.png,
  54_offline_network_log_shows_failed_20260813.png. Severity kept at High;
  this repro raises confidence this is a general defect rather than one
  confined to a couple of edge-case call sites.

Regression test: not added. `RewriteScreen` needs `RewriteController`,
  `ModelsController`, `SettingsController`, `ShareIntentBridge`,
  `ProviderRegistry`, and `ConfigStore` as ancestors just to build, and
  `RewriteController` itself needs `EngineRegistry`, `StorageService`,
  `ConfigStore`, `TargetRouter`, and `ActiveRequestRegistry` to
  construct — substantially heavier scaffolding than
  `audience_list_screen_test.dart`'s single-`ConfigStore` setup. More
  importantly, the root cause here is not yet known (see above), so a
  test written now could only assert "no SnackBar appears," which is a
  test of the bug's *symptom*, not its cause — it would keep passing
  even after an unrelated change, without the real fix landing.
  Recommend adding a widget test once the actual mechanism (root
  `Overlay`/`Navigator` wiring vs. something screen-specific) is
  identified.
