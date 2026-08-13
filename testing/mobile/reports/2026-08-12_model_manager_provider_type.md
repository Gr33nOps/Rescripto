ID:               PROVIDER-001
Severity:         High
Area:             App-wide (state management wiring)
Feature:          Models tab / anything that watches `ModelsController`'s
                   underlying `ModelManager`
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from the working tree during mobile QA
                   environment setup, 2026-08-12 (semantics-identifier
                   commit not yet made — see setup report for exact diff)
Preconditions:    Fresh install, first launch (onboarding not yet completed)
Steps to reproduce:
  1. Launch Rescripto for the first time (onboarding screen shows).
  2. Tap "Get started" with the default "Private & Offline" mode selected.
Expected behavior:
  App navigates to the main Rewrite screen (bottom nav: Rewrite / History /
  Models / Settings) without error.
Actual behavior:
  A Flutter red error screen replaces the body content immediately after
  navigating past onboarding:

    Tried to use Provider with a subtype of Listenable/Stream
    (ModelManager).

    This is likely a mistake, as Provider will not automatically update
    dependents when ModelManager is updated. Instead, consider changing
    Provider for more specific implementation that handles the update
    mechanism, such as:

    - ListenableProvider
    - ChangeNotifierProvider
    - ValueListenableProvider
    - StreamProvider

    Alternatively, if you are making your own provider, consider using
    InheritedProvider.

  The bottom navigation bar is still visible and tapping other tabs still
  works (confirmed History/Models/Settings icons render), but the body of
  whichever screen is active when this fires shows the error screen instead
  of real content.
Reproducibility: Always (seen on first cold-start reproduction; not yet
                  re-tested across multiple runs — flag as "Always" pending
                  a second confirmation pass)
Screenshot/video: testing/mobile/screenshots/rescripto_rewrite_screen.png
                  (also testing/mobile/screenshots/rescripto_launch_smoketest.png
                  for the onboarding screen immediately prior)
Relevant logs:    Not captured in logcat — package:provider's debug check
                  throws and Flutter's error widget renders it in-app
                  before the adb logcat dump was taken (the log tag/timing
                  didn't line up.) The screenshot is the primary evidence;
                  re-run testing/mobile/collect_logs.ps1 -Follow while
                  reproducing to catch it in logcat, if a log is needed.

## Update 2026-08-12 (later same day): re-confirmed, wider blast radius, not first-run-only

Re-tested on a fresh debug build off HEAD `2365240` ("Bump version to 1.1.1
for release" — i.e. this bug is present in the current release-candidate
commit). Findings:

- **Reproduces on every app launch**, not just the first cold start after
  onboarding. Force-stopped the app (`adb shell am force-stop`) and
  relaunched with onboarding already completed — the Rewrite tab still
  shows the exact same red error screen immediately. This is not a
  first-run edge case; it fires every time `ModelManager` is first read via
  Provider, which happens on every process start.
- **Blast radius confirmed**: both the **Rewrite** tab and the **Models**
  tab crash with a red error screen. Models shows a related but distinct
  message on top: `Bad state: Tried to read a provider that threw during
  the creation of its value. The exception occurred during the creation of
  type ModelsController.` — confirming `ModelsController` (and presumably
  `RewriteController`) transitively depends on the mis-registered
  `Provider<ModelManager>`, so the failure cascades to every controller
  that reads it.
- **History and Settings tabs are unaffected** — both render normally,
  bottom nav works, Settings' own screen (Appearance, Processing mode,
  Editor mode radios, etc.) is fully interactive.
- **Blast radius is wider than "the Rewrite/Models tabs"**: it follows any
  code path that reaches `Provider<ModelManager>`, including indirectly.
  Traced via `lib/state/app_providers.dart:175-183` —
  `Provider<TargetRouter>`'s `isLocalModelInstalled` closure calls
  `ctx.read<ModelsController>()`, whose own `create` (line 167) calls
  `ctx.read<ModelManager>()`. So **any** screen that calls
  `context.read<TargetRouter>().route(...)` also trips this, even though
  those screens have nothing to do with models on their face:
  - **Tone editor** (`lib/screens/authoring/tone_editor_screen.dart:63`,
    called directly in `build()`) — opening any tone from Settings > Tones
    (e.g. "Professional") shows the same red error screen immediately.
    Confirmed live. Hardware back does recover cleanly back to the Tones
    list afterward.
  - **Workflow editor** (`lib/screens/authoring/workflow_editor_screen.dart:144`,
    called from `_addStep`, a button callback rather than `build()`) —
    tapping "Add step" on a new/existing workflow throws the identical
    `Bad state: Tried to read a provider that threw during the creation of
    its value` exception, confirmed via logcat
    (`testing/mobile/logs/logcat_20260812_170726.txt:738-739`). Because
    this fires from a button callback instead of `build()`, Flutter does
    **not** show a red error screen here — the exception is caught by the
    default zone error handler and logged, and the UI just does *nothing*:
    no bottom sheet opens, no error message, no feedback at all. This is
    arguably worse for a real user than the Rewrite/Models crash, which at
    least visibly explains that something broke — "Add step" instead looks
    like a dead button with zero signal that anything went wrong.
  - **Audience editor is unaffected** — it doesn't call `TargetRouter`, so
    it opens and works normally regardless of this bug.
- Practical effect: with this build, the app's two primary screens
  (Rewrite — the whole point of the app — and Models) are **completely
  non-functional on every launch**, not an intermittent or first-run-only
  issue. Given it reproduces unconditionally on the main user-facing
  screen, every launch, in the commit currently tagged for a 1.1.1 release,
  this warrants reconsidering severity as **Critical** rather than High —
  it's a full-app-breaking regression on the primary flow, not a
  contained/workaroundable one.

New screenshots from this pass:
`testing/mobile/screenshots/onboarding_initial_20260812_165244.png`,
`testing/mobile/screenshots/rewrite_provider_error_20260812_165317.png`
(Rewrite tab, post-onboarding), and
`testing/mobile/screenshots/models_provider_error_20260812_165657.png`
(Models tab, same crash cascading through `ModelsController`).
Logs: still not present in logcat for the same reason as before (Flutter
debug-mode Provider assertion renders in-app before logcat capture); see
`testing/mobile/logs/logcat_20260812_165324.txt` for the surrounding dump
(no Provider/ModelManager lines — confirms it doesn't surface in logcat by
default).
Suspected cause:  `lib/state/app_providers.dart:153` registers
                  `Provider<ModelManager>(create: (ctx) => ModelManager(...), ...)`
                  as a plain `Provider`, but `ModelManager` is a `Listenable`
                  (`ChangeNotifier`-based, per `lib/services/model_manager.dart`).
                  Nine lines below it, `SettingsController` — also a
                  `ChangeNotifier` — is correctly registered via
                  `ChangeNotifierProvider<SettingsController>(...)`, so this
                  looks like a one-off oversight rather than a deliberate
                  choice. This is a package:provider debug-mode assertion
                  (`Provider.debugCheckInvalidValueType`), so it is likely
                  compiled out in release/profile builds, but the underlying
                  issue is real: if `ModelManager` notifies listeners and
                  nothing above it converts that into `notifyListeners()`
                  the `Provider` package understands, dependents relying on
                  `context.watch` may not rebuild when it changes even in
                  release. Not fixed as part of this QA environment setup —
                  reported per the "don't change application behavior
                  without being asked" rule; recommend a widget test that
                  pumps the app past onboarding and asserts no
                  `FlutterError` is thrown, once this is addressed.
