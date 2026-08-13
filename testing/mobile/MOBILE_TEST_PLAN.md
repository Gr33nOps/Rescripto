# Rescripto mobile QA plan

Read this before running a QA pass. It's written for a future Claude
session with no memory of this one — it assumes nothing about what changed
since this was written except what's in the repo right now.

## Before you start

1. Read `testing/mobile/README.md` for the environment shape and why the
   test device is arm64, not the usual x86_64.
2. `git log --oneline -20` and skim recently changed files under `lib/` —
   know what's actually different before you go looking for bugs in it.
3. `testing\mobile\start_test_device.ps1` — boot the emulator, wait for full
   boot.
4. `testing\mobile\build_and_install.ps1` — build the current debug APK,
   install, launch. Re-run this any time `lib/` or `android/` changed since
   your last pass.
5. Confirm Appium MCP is connected (`claude mcp get appium-mcp`) and start a
   session using `testing/mobile/capabilities.json`.
6. Confirm the app is in the foreground: `adb shell dumpsys activity
   activities | findstr mResumedActivity` should show
   `com.rescripto.rescripto/.MainActivity`.

## How to find things reliably

Prefer `Semantics.identifier` values over visible text — text changes with
copy edits, identifiers don't. The identifiers already in the codebase are
listed in the setup report (search the repo for `Semantics(` and
`identifier:` under `lib/` if that report isn't at hand — every important
interactive control has one, named predictably: screen/feature prefix +
control name, e.g. `rewrite_input`, `rewrite_button`, `model_download_<id>`,
`history_item_<id>`, `tone_option_<id>`). If a control you need to test has
no identifier, that's a gap worth noting in your report (or fixing directly
if it's a trivial one-line `Semantics` wrap — see Phase constraints below:
identifiers may be added, behavior must not change).

Fall back to visible text (button labels, tile titles) or the UiAutomator2
UI-hierarchy dump when an identifier doesn't exist yet.

## What NOT to do

- Don't change application behavior to make a test pass.
- Don't trigger expensive cloud API calls or download large local models
  just to prove automation works — a smoke test only needs to reach the
  point where a real request *would* go out.
- Don't silently "fix" a bug you find while exploring — record it (Bug
  Reporting Format below) unless it's trivial and clearly in scope for
  the pass you were asked to do.
- Don't call something fixed because it worked once. Re-run flaky-looking
  failures at least once before writing them up as confirmed.

## Exploration checklist (run through this every pass)

1. Every reachable screen: Rewrite, History, Models, Settings, and from
   Settings → Tones / Audiences / Workflows (each has list + editor
   screens), Privacy & network, Cloud providers (+ add/edit provider),
   Backup (+ WebDAV sync), Network log. Plus onboarding (first run only —
   use `reset_app.ps1` to get back there) and the History detail screen.
2. Every meaningful control on each screen (see Feature-specific tests
   below for the exhaustive per-screen list).
3. Normal paths, then invalid inputs, then rapid repeated taps (does a
   button double-fire? does a disabled state actually block input?).
4. Back navigation from every screen — hardware/gesture back and the AppBar
   back arrow, mid-flow (e.g. back out of a dialog, back out of the
   provider-add bottom sheet).
5. Loading / empty / error / success states — Models screen while
   downloading, History with zero entries, Network log empty state, a
   forced provider connection failure.
6. Persistence: change a setting, force-stop the app
   (`reset_app.ps1` without `-Relaunch` force-stops only if you clear data —
   for a persistence check use `adb shell am force-stop com.rescripto.rescripto`
   directly, then relaunch), confirm the change survived.
7. Dark/light theme — Settings → Appearance → each of the three options,
   confirm it actually applies (screenshot each).
8. Keyboard interaction — every text field: does the right keyboard type
   show, does submit/newline behave as expected (the rewrite source field
   wants newline on Enter, not submit).
9. Rotation — `adb shell settings put system accelerometer_rotation 0` then
   `adb shell settings put system user_rotation 1` (landscape) and back;
   confirm no crash and state survives (source text, in-flight streaming
   panel, etc.).
10. Offline/network-loss — `adb shell svc wifi disable` + `adb shell svc
    data disable` (emulator has no cellular radio to toggle separately, but
    disabling both approximates offline); confirm Local mode still works
    fully and Cloud/Hybrid fail with a clear in-app error, not a crash.
11. Screenshot liberally throughout — `testing/mobile/screenshots/`,
    filename pattern `<area>_<state>_<yyyyMMdd_HHmmss>.png`.
12. Pull logs after anything suspicious:
    `testing\mobile\collect_logs.ps1` (or `-Follow` while reproducing).

## Feature-specific tests

### Rewrite (main screen)

Controls: `rewrite_input` (source text), paste/clear icons, `speech_button`
(mic dictation), `tone_selector` (`tone_option_<id>` chips), Pro mode only:
`strength_selector`, `length_selector`, `audience_selector`
(`audience_option_<id>`), `rewrite_instruction_input`,
`variant_count_selector` (1/2/3), `rewrite_button` (doubles as
`cancel_generation` target while running via the AppBar stop icon),
`ui_mode_toggle` (Simple ↔ Pro).

Input coverage — run each through both Local and Cloud/Hybrid (see
Processing below) where feasible:
- Empty input (expect a "Nothing to rewrite yet" snackbar, no crash)
- Very short text (a few words)
- Long text (near the 8000-char field limit)
- Broken grammar / run-on sentences
- Casual text vs. text that should read as already-professional
- Numbers, prices, dates, email addresses, URLs — confirm they survive the
  rewrite recognizably (not mangled or dropped)
- Markdown syntax and fenced code blocks — confirm the model doesn't
  destroy structure it wasn't asked to touch
- Emoji and non-Latin Unicode
- Multiline text (multiple paragraphs)

### Rewrite settings

Exercise every tone, every audience toggle, every intensity value, every
length value, and 1/2/3 variant counts at least once each. Confirm Pro-only
controls disappear in Simple mode and their last values are restored when
switching back to Pro (`RewriteController.enterSimpleMode`/`enterProMode` —
this is a documented pinning behavior, worth specifically probing: set a
Pro value, drop to Simple, change nothing, go back to Pro, confirm the
value held).

### Results

Controls: `variant_selector` (`variant_1`/`variant_2`/`variant_3`),
`result_view_toggle` (`show_original`/`show_rewrite`), `copy_result`,
`share_result`, `rewrite_again_button`, `insert_result` (only visible when
Rescripto was opened via PROCESS_TEXT/share and a result exists).

- Switching variants updates the displayed text.
- Copy → check clipboard actually has the displayed variant, not always V1
  (this was a real historical bug per the code comments — verify it stays
  fixed).
- Share → confirm the Android share sheet opens with the right text.
- Insert & return → only testable via the PROCESS_TEXT flow (see
  Integrations below); confirm it sends back the *currently selected*
  variant, not always V1.
- A completed rewrite should appear in History afterward.

### Processing modes

Settings → Processing mode: Local / Cloud / Hybrid. Test each
independently:
- **Local**: works fully with airplane mode / network disabled. Requires an
  installed model (Models tab) — if none is installed, the Rewrite screen
  should show the "install a model first" banner and route Tap-to-fix to
  Models, not silently fail.
- **Cloud**: requires a configured, enabled provider with a key (Settings →
  Cloud providers). No key configured → expect the "add a cloud provider"
  banner, not a crash. With a key: this is a real network call to a paid
  API — don't run more than the minimum needed to confirm the plumbing
  works, and only if the user has actually configured a provider. If no
  provider is configured and you're not able to add one (no API key
  available), **report this as blocked**, not passed.
- **Hybrid**: prefers local, asks consent before falling back to cloud
  (local→cloud) but never asks the other way (cloud→local, per code
  comments — cloud failing is assumed safe to retry locally without
  prompting). Test the local-failure path by having no model installed
  while Hybrid is selected and confirm the consent dialog appears and
  names the provider/model plainly.

### Local models (Models tab)

For each bundled/downloadable model reasonably sized for the emulator disk:
attempt download, record MB/s and ETA behavior, confirm the progress UI
(`model_download_<id>` → progress bar → installed state), test Cancel
mid-download (`model_cancel_<id>`), test Delete
(`model_delete_<id>` with the "active model" vs. "not active" confirmation
copy), test "Use this model" (`model_select_<id>`) switches the active
model. Record for each model actually run through a rewrite: success/crash/
load failure/refusal/obvious hallucination or meaning drift/generation time
(shown in the result's token/sec stat chip)/UI freezing during generation.
Larger is not automatically better — record what you actually observe, not
an assumption.

Remember: this emulator is x86_64 (see README for why — arm64 system images
no longer boot on this x86_64 host at all), running an arm64-v8a-only APK.
The APK installs and launches fine, but on-device generation dlopen's
`libllama.so`/`libwhisper.so`, which has **not** been confirmed to work here.
If a Local-mode rewrite fails with `UnsatisfiedLinkError` or `dlopen
failed`, that's an environment limitation, not an app bug — mark Local
model tests **Blocked** on this machine and say so plainly, don't report it
as a failure.

### Android integrations

- **PROCESS_TEXT**: from a text field in another app (e.g. long-press
  selected text in Chrome or Settings), the text-selection toolbar should
  offer Rescripto. Tapping it opens Rescripto with `awaitingProcessTextResult`
  true (the `_ProcessTextBanner` should show), the source text pre-filled,
  and after a rewrite, `insert_result` sends the selected variant back to
  the caller and closes Rescripto. Navigating away instead should count as
  declining (per `MainActivity.kt`'s documented behavior) — confirm the
  caller app doesn't hang waiting.
- **Share target (ACTION_SEND)**: from another app's Share sheet, "Share" →
  Rescripto with plain text should behave the same as PROCESS_TEXT for
  pre-filling source text.
- **Quick Settings tile**: add the Rescripto tile to Quick Settings
  (`adb shell` can't easily trigger this — do it manually via the emulator
  UI, or note as a manual-only check if automation can't reach the QS
  panel), tap it, confirm it opens Rescripto in a testable state.
- **Permissions**: `RECORD_AUDIO` is requested on first mic tap — confirm
  the system permission dialog appears, and both Allow and Deny paths leave
  the app in a sane state (Deny should show a clear "no mic access" message
  via `MicButton`, not a silent failure).
- **Clipboard**: Paste icon in the source field reads real clipboard
  content (`adb shell am broadcast` can't set clipboard directly — set it
  via a text field in another app, or via Appium's clipboard-set action if
  the MCP exposes one).

### Storage and persistence

- History: entries persist across relaunch; delete-one and clear-all both
  actually remove rows (re-open History and confirm, don't just trust the
  UI update).
- Settings: every toggle/radio persists across a full app restart
  (`adb shell am force-stop` then relaunch, not just backgrounding).
- Model persistence: an installed model survives relaunch; the "active
  model" selection survives relaunch.
- `reset_app.ps1` (clears app data): confirm this actually returns the app
  to onboarding on next launch — if it doesn't, that's a bug (Settings →
  onboarding-completed flag should live in the data `pm clear` wipes).
- Backup: export with a passphrase, confirm a file share sheet appears;
  restore that file back in (preview screen should show accurate counts
  before committing); confirm passphrase mismatch and wrong-file cases show
  clear errors, not crashes.
- WebDAV sync: only testable if a WebDAV server is actually configured —
  otherwise report blocked, don't fabricate a pass.

## Processing modes / models / integrations you can't test

If something needs credentials, network access, or hardware you don't have
in this environment, say so explicitly in the report as **Blocked**, with
what would unblock it. Never mark it Passed.

## Bug report format

One block per issue, saved as a dated markdown file under
`testing/mobile/reports/` (e.g. `2026-08-12_rewrite_variant_bug.md`):

```
ID:               (short slug, e.g. RESULT-VIEW-001)
Severity:         Critical | High | Medium | Low
Area:             (screen/feature)
Feature:
Device/API:       Rescripto_Test, Android 15 (API 35), arm64-v8a
App build/commit: (git rev-parse --short HEAD at test time)
Preconditions:
Steps to reproduce:
Expected behavior:
Actual behavior:
Reproducibility:  Always | Intermittent (n/m attempts) | Once
Screenshot/video: (path under testing/mobile/screenshots or recordings)
Relevant logs:    (path under testing/mobile/logs, or inline excerpt)
Suspected cause:  (optional, if evident from logs/code)
```

Severity guide: **Critical** = crash, data loss, or a security/privacy
guarantee broken (e.g. a kill-switch not actually blocking network).
**High** = a core flow (rewrite, save, install) broken or badly wrong.
**Medium** = a real bug with a workaround. **Low** = cosmetic/copy issue.

## Permanent regression tests

Appium/exploratory testing is for black-box, system-level, and visual
verification — it is not meant to be encoded 1:1 into automated tests. But
when you find a **deterministic** application bug (not a flaky/environment
issue), add a permanent regression test using the project's existing
architecture before/instead of just reporting it:

- Pure logic bug (a model, a store, a controller) → unit test alongside the
  existing ones in `test/` (e.g. `config_store_test.dart`,
  `rewrite_controller_test.dart` — follow their existing style).
- A widget rendering/state bug → a Flutter widget test.
- A full end-to-end flow that should stay stable → `integration_test/` (create
  the directory if it doesn't exist yet; there is no existing
  `integration_test/` suite in this repo as of this writing).

Note the current baseline: `flutter test` is 362/363 passing. The one
failure (`backup_service_test.dart`, a 30s timeout on the encryption
round-trip test) predates this QA setup — see README's "Known pre-existing
issues." Don't count it against a QA pass unless you've changed something
that could plausibly affect it.
